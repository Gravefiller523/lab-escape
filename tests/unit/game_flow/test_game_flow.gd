extends GutTest
## Tests for game_flow (docs/systems/game_flow.md). Each "PC" is a SubViewport with its own
## multiplayer, Net and GameFlow (with a fake scene changer that only records what it was asked to load).

const PORT: int = 18080
const WAIT: float = 5.0

var _pcs: Array[Node] = []
## PC -> the scene paths its GameFlow asked to load.
var _loaded: Dictionary[Node, PackedStringArray] = {}
## PC -> the level kinds its GameFlow asked to build.
var _built: Dictionary[Node, PackedStringArray] = {}


static func _department(id: StringName, order_hint: int, floor_count: int = 0) -> DepartmentData:
	var department := DepartmentData.new()
	department.id = id
	department.display_name = String(id).capitalize()
	department.order_hint = order_hint
	department.floor_count = floor_count
	department.boss_id = &"boss_test"
	return department


## Test departments are added to the registry once (it has no "remove"). Their very low order_hints
## put them first in every run.
func before_all() -> void:
	for department: DepartmentData in [_department(&"department_test_first", -1000),
			_department(&"department_test_second", -999, 2)]:
		if not ContentRegistry.has_content(department.id):
			ContentRegistry.register_content(department)


func _config() -> GameConfig:
	var config := GameConfig.new()
	config.elevator_ride_seconds = 0.05
	config.lift_ride_seconds = 0.05
	config.run_summary_seconds = 0.05
	config.floor_load_timeout = 3.0
	config.floors_per_department = 5
	config.departments_per_run = 2
	# CHANGED 2026-10-31: a department every floor; a boss floor every 6th floor; 12 floors in a test run.
	config.run_floor_count = 12
	config.boss_every_floors = 6
	return config


func _make_pc(config: GameConfig) -> Node:
	var pc := SubViewport.new()
	pc.name = "Pc%d" % _pcs.size()
	add_child(pc)
	get_tree().set_multiplayer(SceneMultiplayer.new(), pc.get_path())
	var net := NetService.new()
	net.name = "Net"
	net.use_config(config)
	pc.add_child(net)
	_loaded[pc] = PackedStringArray()
	_built[pc] = PackedStringArray()
	var flow := GameFlowService.new()
	flow.name = "GameFlow"
	flow.use_test_setup(net, config, func(path: String) -> void: _loaded[pc].append(path),
		func(level: Dictionary) -> void: _built[pc].append(str(level.get("kind", ""))))
	pc.add_child(flow)
	_pcs.append(pc)
	return pc


func _flow(pc: Node) -> GameFlowService:
	return pc.get_node("GameFlow") as GameFlowService


func _net(pc: Node) -> NetService:
	return pc.get_node("Net") as NetService


func _state_is(pc: Node, state: GameFlowService.State) -> Callable:
	return func() -> bool: return _flow(pc).get_state() == state


func _host_and_client(config: GameConfig, client_too: bool = true) -> Array[Node]:
	var host := _make_pc(config)
	var server := ENetMultiplayerPeer.new()
	assert_eq(server.create_server(PORT, 8), OK)
	host.multiplayer.multiplayer_peer = server
	var pcs: Array[Node] = [host]
	if client_too:
		pcs.append(await _join(config))
	return pcs


func _join(config: GameConfig) -> Node:
	var client := _make_pc(config)
	var peer := ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", PORT)
	client.multiplayer.multiplayer_peer = peer
	await wait_until(func() -> bool: return _net(_pcs[0]).get_player_ids().size() == _pcs.size(), WAIT)
	return client


func after_each() -> void:
	var paths: Array[NodePath] = []
	var peers: Array[MultiplayerPeer] = []
	for pc: Node in _pcs:
		paths.append(pc.get_path())
		peers.append(pc.multiplayer.multiplayer_peer)
		pc.free()
	for index: int in paths.size():
		if peers[index] != null:
			peers[index].close()
		get_tree().set_multiplayer(null, paths[index])
	_pcs.clear()
	_loaded.clear()
	_built.clear()


func test_state_order_menu_breakroom_run_floor() -> void:
	var pc := _make_pc(_config())
	var flow: GameFlowService = _flow(pc)
	assert_eq(flow.get_state(), GameFlowService.State.BOOT, "a test scene: not in charge yet")
	EventBus.elevator_start_accepted.emit()
	assert_false(flow.is_in_run(), "outside the Break Room the elevator starts nothing")
	flow.go_to_break_room()
	await wait_until(_state_is(pc, GameFlowService.State.BREAK_ROOM), WAIT)
	assert_eq(flow.get_state(), GameFlowService.State.BREAK_ROOM)
	assert_eq(_loaded[pc][-1], GameFlowService.WORLD_SCENE, "the game world is loaded")
	assert_eq(_built[pc][-1], GameFlowService.LEVEL_BREAK_ROOM, "with the Break Room in it")

	watch_signals(EventBus)
	EventBus.elevator_start_accepted.emit()
	assert_eq(flow.get_state(), GameFlowService.State.LOADING_FLOOR, "the lift rides while floor 1 loads")
	assert_true(flow.is_in_run())
	assert_signal_emitted(EventBus, "run_started")
	await wait_until(_state_is(pc, GameFlowService.State.ON_FLOOR), WAIT)
	assert_eq(flow.get_state(), GameFlowService.State.ON_FLOOR)
	assert_eq(_built[pc][-1], GameFlowService.LEVEL_FLOOR, "a floor was built around the lift")
	assert_signal_emitted(EventBus, "floor_loading")
	assert_signal_emitted(EventBus, "floor_ready")
	assert_eq(flow.get_run().floor_number, 1)
	# CHANGED 2026-10-31: a department is rolled for every floor of the run.
	assert_eq(flow.get_run().department_ids.size(), 12, "one department per floor")
	assert_eq(flow.get_run().get_department_id(), flow.get_run().department_ids[0])

	EventBus.lift_departed.emit(1)
	await wait_until(func() -> bool: return flow.get_run().floor_number == 2 and flow.get_state() == GameFlowService.State.ON_FLOOR, WAIT)
	assert_eq(flow.get_run().floor_number, 2, "the lift goes to the next floor")


func test_every_sixth_floor_is_a_boss_floor_and_the_last_one_ends_the_run() -> void:
	# CHANGED 2026-10-31 (Zachary, F1 and F3): boss floors every boss_every_floors floors, run_floor_count floors.
	var pc := _make_pc(_config())
	var flow: GameFlowService = _flow(pc)
	flow.go_to_break_room()
	await wait_until(_state_is(pc, GameFlowService.State.BREAK_ROOM), WAIT)
	flow.debug_go_to_floor(5)
	await wait_until(_state_is(pc, GameFlowService.State.ON_FLOOR), WAIT)
	assert_eq(flow.get_run().floor_in_department, 5, "floor 5 is the 5th of its block")
	watch_signals(EventBus)
	EventBus.lift_departed.emit(5)
	await wait_until(_state_is(pc, GameFlowService.State.BOSS_FIGHT), WAIT)
	assert_eq(flow.get_run().floor_number, 6)
	assert_true(flow.get_run().is_boss_floor, "floor 6 is a boss floor")
	var boss_department: DepartmentData = flow.get_current_department()
	assert_signal_emitted_with_parameters(EventBus, "boss_floor_started", [boss_department.boss_id])
	# The lift (cargo_lift) only leaves a boss floor once the boss is beaten; then it goes on.
	EventBus.lift_departed.emit(6)
	await wait_until(_state_is(pc, GameFlowService.State.ON_FLOOR), WAIT)
	assert_eq(flow.get_run().floor_number, 7)
	assert_false(flow.get_run().is_boss_floor)
	assert_eq(flow.get_run().floor_in_department, 1, "a new block of floors")

	# Floor 12 is the last floor (a boss floor): beating its boss wins the run.
	flow.debug_go_to_floor(12)
	await wait_until(_state_is(pc, GameFlowService.State.BOSS_FIGHT), WAIT)
	EventBus.lift_departed.emit(12)
	assert_signal_emitted_with_parameters(EventBus, "run_ended", [GameFlowService.RESULT_ESCAPED])
	await wait_until(_state_is(pc, GameFlowService.State.BREAK_ROOM), WAIT)
	assert_false(flow.is_in_run())


func test_a_department_is_rolled_every_floor() -> void:
	var config := _config()
	config.run_floor_count = 18
	var flow: GameFlowService = _flow(_make_pc(config))
	var floors: Array[StringName] = flow.floor_departments(42)
	assert_eq(floors.size(), 18, "one department per floor")
	assert_eq(flow.floor_departments(42), floors, "same seed, same departments")
	var runs: Dictionary[String, bool] = {}
	for run_seed: int in 20:
		var ids: Array[StringName] = flow.floor_departments(run_seed)
		runs[str(ids)] = true
		for index: int in range(1, ids.size()):
			assert_ne(ids[index], ids[index - 1], "seed %d floor %d: never the same department twice in a row" % [run_seed, index + 1])
		for boss_floor: int in [6, 12, 18]:
			var department: DepartmentData = flow.get_department(ids[boss_floor - 1])
			assert_true(department.boss_floors and ContentRegistry.has_content(department.boss_id),
				"seed %d: boss floor %d is a department with its own boss (%s)" % [run_seed, boss_floor, department.id])
	assert_gt(runs.size(), 1, "other seeds, other departments")
	var run := RunState.new()
	run.department_ids = floors
	assert_true(flow.place_on_floor(run, 13))
	assert_eq(run.get_department_id(), floors[12], "floor 13's department")
	assert_eq(run.floor_in_department, 1)
	assert_false(run.is_boss_floor)
	assert_true(flow.place_on_floor(run, 18))
	assert_true(run.is_boss_floor)
	assert_false(flow.place_on_floor(run, 19), "a run has run_floor_count floors")


func test_debug_floor_with_a_department_sets_that_floor() -> void:
	var pc := _make_pc(_config())
	var flow: GameFlowService = _flow(pc)
	flow.go_to_break_room()
	await wait_until(_state_is(pc, GameFlowService.State.BREAK_ROOM), WAIT)
	flow.debug_go_to_floor(3, &"department_test_second")
	await wait_until(_state_is(pc, GameFlowService.State.ON_FLOOR), WAIT)
	assert_eq(flow.get_run().floor_number, 3)
	assert_eq(flow.get_run().get_department_id(), &"department_test_second")


func test_department_order_is_same_for_same_seed() -> void:
	var config := _config()
	config.departments_per_run = 0
	var flow: GameFlowService = _flow(_make_pc(config))
	for dept_id: StringName in [&"department_test_tie_a", &"department_test_tie_b", &"department_test_tie_c"]:
		if not ContentRegistry.has_content(dept_id):
			ContentRegistry.register_content(_department(dept_id, -500))
	var order: Array[StringName] = flow.department_order(42)
	assert_eq(flow.department_order(42), order, "same seed, same order")
	assert_eq(order.slice(0, 2), [&"department_test_first", &"department_test_second"] as Array[StringName],
		"lower order_hint comes first")
	var orders: Dictionary[String, bool] = {}
	for run_seed: int in 30:
		orders[str(flow.department_order(run_seed).slice(2, 5))] = true
	assert_gt(orders.size(), 1, "ties are shuffled by the seed")


func test_new_department_file_joins_rotation() -> void:
	var config := _config()
	config.departments_per_run = 0
	var flow: GameFlowService = _flow(_make_pc(config))
	var fresh := _department(&"department_test_new", 50)
	if not ContentRegistry.has_content(fresh.id):
		ContentRegistry.register_content(fresh)
	assert_true(flow.department_order(1).has(&"department_test_new"), "a new DepartmentData is in runs")
	var hidden := _department(&"department_test_hidden", 50)
	hidden.in_run_rotation = false
	if not ContentRegistry.has_content(hidden.id):
		ContentRegistry.register_content(hidden)
	assert_false(flow.department_order(1).has(&"department_test_hidden"), "unless in_run_rotation is off")


func test_team_wipe_ends_run_and_returns_to_break_room() -> void:
	var pc := _make_pc(_config())
	var flow: GameFlowService = _flow(pc)
	flow.go_to_break_room()
	await wait_until(_state_is(pc, GameFlowService.State.BREAK_ROOM), WAIT)
	flow.start_run(77)
	await wait_until(_state_is(pc, GameFlowService.State.ON_FLOOR), WAIT)
	assert_eq(flow.get_run().run_seed, 77)
	watch_signals(EventBus)
	EventBus.team_wiped.emit()
	assert_eq(flow.get_state(), GameFlowService.State.RUN_SUMMARY)
	assert_signal_emitted_with_parameters(EventBus, "run_ended", [GameFlowService.RESULT_WIPED])
	await wait_until(_state_is(pc, GameFlowService.State.BREAK_ROOM), WAIT)
	assert_false(flow.is_in_run())
	assert_eq(_loaded[pc][-1], GameFlowService.WORLD_SCENE, "the game world is loaded")
	assert_eq(_built[pc][-1], GameFlowService.LEVEL_BREAK_ROOM, "with the Break Room in it")


func test_client_follows_the_host_through_the_run() -> void:
	var pcs: Array[Node] = await _host_and_client(_config())
	var host: Node = pcs[0]
	var client: Node = pcs[1]
	_flow(host).go_to_break_room()
	await wait_until(_state_is(host, GameFlowService.State.BREAK_ROOM), WAIT)
	await wait_until(_state_is(client, GameFlowService.State.BREAK_ROOM), WAIT)
	assert_eq(_flow(client).get_state(), GameFlowService.State.BREAK_ROOM, "the client goes too")
	_flow(host).start_run(5)
	await wait_until(_state_is(client, GameFlowService.State.ON_FLOOR), WAIT)
	assert_eq(_flow(client).get_state(), GameFlowService.State.ON_FLOOR)
	assert_eq(_flow(host).get_state(), GameFlowService.State.ON_FLOOR)
	assert_eq(_flow(client).get_run().run_seed, 5, "the client has the host's run")
	assert_eq(_built[client][-1], GameFlowService.LEVEL_FLOOR, "and built the floor itself")


func test_late_joiner_gets_the_current_floor() -> void:
	var config := _config()
	var pcs: Array[Node] = await _host_and_client(config, false)
	var host: Node = pcs[0]
	_flow(host).go_to_break_room()
	await wait_until(_state_is(host, GameFlowService.State.BREAK_ROOM), WAIT)
	_flow(host).start_run(9)
	await wait_until(_state_is(host, GameFlowService.State.ON_FLOOR), WAIT)
	var client: Node = await _join(config)
	await wait_until(_state_is(client, GameFlowService.State.ON_FLOOR), WAIT)
	assert_eq(_flow(client).get_state(), GameFlowService.State.ON_FLOOR, "joined straight onto the floor")
	assert_eq(_flow(client).get_run().run_seed, 9)
	assert_eq(_built[client][-1], GameFlowService.LEVEL_FLOOR)
	assert_eq(_loaded[client][-1], GameFlowService.WORLD_SCENE, "the joiner loaded the game world")
	_flow(client).go_to_break_room()
	assert_eq(_flow(client).get_state(), GameFlowService.State.ON_FLOOR, "a late 'go to the Break Room' from the menu is ignored")


func test_two_lift_presses_go_up_one_floor() -> void:
	var config := _config()
	# A ride long enough that the third press lands while everyone is still on the way.
	config.lift_ride_seconds = 0.5
	var pc := _make_pc(config)
	var flow: GameFlowService = _flow(pc)
	flow.go_to_break_room()
	await wait_until(_state_is(pc, GameFlowService.State.BREAK_ROOM), WAIT)
	flow.start_run(3)
	await wait_until(_state_is(pc, GameFlowService.State.ON_FLOOR), WAIT)
	EventBus.lift_departed.emit(1)
	EventBus.lift_departed.emit(1)
	await wait_physics_frames(2)
	EventBus.lift_departed.emit(1)
	await wait_until(func() -> bool: return flow.get_run().floor_number == 2 and flow.get_state() == GameFlowService.State.ON_FLOOR, WAIT)
	await wait_seconds(0.5)
	assert_eq(flow.get_run().floor_number, 2, "several presses at once still go up one floor")
