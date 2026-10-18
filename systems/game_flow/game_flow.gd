class_name GameFlowService
extends Node
## Autoload "GameFlow". The game's big state machine: main menu, Break Room, elevator ride, floors,
## boss fights and the run summary. It owns the run (seed, floor number, department order) and loads
## the main scenes on every PC. Spec: docs/systems/game_flow.md.
##
## The host decides every change and tells the clients (reliable RPCs); each PC then loads the same
## scene and emits the same EventBus events. GameFlow only takes charge once it has loaded the main
## menu or the Break Room (or the game started in one); in a system's own test scene it stays out of
## the way, so test scenes and GUT tests are left alone.
##
## STUBS until other systems exist:
## - cargo_lift and bosses: level_gen's floor scene has "Depart" and "Defeat the boss" stand-in buttons.
## - departments: with no department content yet, runs use one placeholder department.

enum State { BOOT, MAIN_MENU, BREAK_ROOM, ELEVATOR_RIDE, LOADING_FLOOR, ON_FLOOR, BOSS_FIGHT, RUN_SUMMARY }

const MAIN_MENU_SCENE: String = "res://systems/ui/main_menu_background.tscn"
const BREAK_ROOM_SCENE: String = "res://systems/break_room/break_room.tscn"
## Every floor is this scene; level_gen builds the rooms into it.
const FLOOR_SCENE: String = LevelService.FLOOR_SCENE
## Where the host waits while the clients change scene.
const LOADING_SCENE: String = "res://systems/game_flow/loading_screen.tscn"
## STUB (department content): used when no DepartmentData is in the run rotation.
const PLACEHOLDER_DEPARTMENT_ID: StringName = &"department_placeholder"
## STUB (department content): the placeholder department's lift part.
const PLACEHOLDER_LIFT_PART_ID: StringName = &"prop_lift_part_zoology"

const RESULT_ESCAPED: StringName = &"escaped"
const RESULT_WIPED: StringName = &"wiped"
const RESULT_ABANDONED: StringName = &"abandoned"
## Seconds between "stop sending player updates" and the clients changing scene (see _transition),
## so updates already on their way arrive while everyone still has the old scene.
const CLIENT_LOAD_DELAY: float = 0.15
## Most frames to wait for a new scene to appear after changing to it.
const SCENE_WAIT_FRAMES: int = 10
## Seconds of waiting for a slow PC before the host is told who it is waiting for.
const SLOW_LOAD_NOTICE_SECONDS: float = 4.0

## The state names, for the console and test scene.
const STATE_NAMES: PackedStringArray = ["BOOT", "MAIN_MENU", "BREAK_ROOM", "ELEVATOR_RIDE", "LOADING_FLOOR",
	"ON_FLOOR", "BOSS_FIGHT", "RUN_SUMMARY"]

var _net: NetService
var _config: GameConfig
## How scenes are changed: func(path: String) -> void. Tests swap in a fake.
var _load_scene: Callable
## How a floor is built from its layout: func(layout: FloorLayout) -> void. Tests swap in a fake.
var _build_floor: Callable
## The current floor's layout (FloorLayout.to_dict()), sent to players who join.
var _layout_data: Dictionary = {}
var _state: State = State.BOOT
var _run: RunState
var _placeholder: DepartmentData
## Host: clients that have loaded the scene of the current transition.
var _built_peers: Dictionary[int, bool] = {}
## Host: the clients a transition is waiting for (players who join during it are already in the new scene).
var _transition_peers: PackedInt32Array = []
## Host: a scene change is under way (the lift or the boss can't start another one).
var _moving: bool = false
var _transition_id: int = 0
## Client: the host has told us where the game is (so a late "go to the Break Room" is ignored).
var _synced_from_host: bool = false
var _peer_seen: MultiplayerPeer
var _was_host: bool = true


## For tests only: a different Net and config, a fake scene changer and floor builder. Call before
## adding to the tree.
func use_test_setup(net: NetService, config: GameConfig, scene_loader: Callable,
		floor_builder: Callable = Callable()) -> void:
	_net = net
	_config = config
	_load_scene = scene_loader
	_build_floor = floor_builder if floor_builder.is_valid() else func(_layout: FloorLayout) -> void: pass


func _ready() -> void:
	if _net == null:
		_net = Net
	if _config == null:
		_config = Config.game
	if not _load_scene.is_valid():
		_load_scene = func(path: String) -> void: get_tree().change_scene_to_file(path)
	if not _build_floor.is_valid():
		_build_floor = func(layout: FloorLayout) -> void: Level.build(layout)
	_peer_seen = multiplayer.multiplayer_peer
	EventBus.elevator_start_accepted.connect(_on_elevator_start_accepted)
	EventBus.lift_departed.connect(_on_lift_departed)
	EventBus.boss_defeated.connect(_on_boss_defeated)
	EventBus.team_wiped.connect(_on_team_wiped)
	_net.set_join_handlers(_join_info, _prepare_for_join)
	if _net == Net:
		_take_charge_of_start_scene.call_deferred()
		_register_console_commands.call_deferred()


# --- Public API -------------------------------------------------------------------------------

func get_state() -> State:
	return _state


func get_state_name() -> String:
	return STATE_NAMES[_state]


## The current run, or null outside a run.
func get_run() -> RunState:
	return _run


## The department we are in, or null outside a run.
func get_current_department() -> DepartmentData:
	if _run == null:
		return null
	return get_department(_run.get_department_id())


func is_in_run() -> bool:
	return _run != null


## Host: start a run from the Break Room. 0 = a random seed (or Config.game.debug_run_seed).
func start_run(run_seed: int = 0) -> void:
	if not _net.is_host() or is_in_run():
		return
	# A Break Room trip still on its way would end this run when it arrives.
	_transition_id += 1
	var run := RunState.new()
	run.run_seed = run_seed
	if run.run_seed == 0:
		run.run_seed = _config.debug_run_seed if _config.debug_run_seed != 0 else randi_range(1, 2147483646)
	run.department_ids = department_order(run.run_seed)
	run.floor_number = 1
	run.department_index = 0
	run.floor_in_department = 1
	run.is_boss_floor = floors_in(get_department(run.department_ids[0])) <= 0
	_run_started_rpc.rpc(run.to_dict())
	_state_rpc.rpc(State.ELEVATOR_RIDE)
	get_tree().create_timer(_config.elevator_ride_seconds).timeout.connect(_load_current_floor)


## Host: end the run. result: &"escaped", &"wiped" or &"abandoned".
func end_run(result: StringName) -> void:
	if not _net.is_host() or not is_in_run() or _state == State.RUN_SUMMARY:
		return
	_run_ended_rpc.rpc(result)
	get_tree().create_timer(_config.run_summary_seconds).timeout.connect(go_to_break_room)


## Host: everyone to the Break Room. A client calls it after joining (it loads the Break Room
## for itself, unless the host already told it to be somewhere else).
func go_to_break_room() -> void:
	if not _net.is_online() or _net.is_host():
		_transition(BREAK_ROOM_SCENE, {})
	elif not _synced_from_host:
		_enter_break_room()


## Local: leave the lobby (or the solo game) and go back to the main menu.
func return_to_main_menu() -> void:
	SteamSession.leave_lobby()
	_drop_run_locally()
	_set_state(State.MAIN_MENU)
	_load_scene.call(MAIN_MENU_SCENE)


## Host, cheats only: jump to a floor. Without a department, floor_number counts across the whole
## run; with one, it is the floor inside that department (floor_count + 1 = its boss floor).
func debug_go_to_floor(floor_number: int, department_id: StringName = &"") -> String:
	if not _net.is_host():
		return "Only the host can change floors."
	if not DebugConsole.cheats_allowed():
		return DebugConsoleService.MSG_NO_CHEATS
	if floor_number < 1:
		return "Floors start at 1."
	var run: RunState = _run
	if run == null:
		run = RunState.new()
		run.run_seed = _config.debug_run_seed if _config.debug_run_seed != 0 else randi_range(1, 2147483646)
		run.department_ids = department_order(run.run_seed)
	if department_id != &"":
		if get_department(department_id) == null:
			return "No department called '%s'." % department_id
		if not run.department_ids.has(department_id):
			run.department_ids.insert(mini(run.department_index, run.department_ids.size()), department_id)
		run.department_index = run.department_ids.find(department_id)
		run.floor_in_department = clampi(floor_number, 1, floors_in(get_department(department_id)) + 1)
		run.floor_number = _first_floor_of(run, run.department_index) + run.floor_in_department - 1
	elif not place_on_floor(run, floor_number):
		return "This run has only %d floors." % total_floors(run)
	run.is_boss_floor = run.floor_in_department > floors_in(get_department(run.get_department_id()))
	if _run == null:
		_run_started_rpc.rpc(run.to_dict())
	else:
		_run = run
	_load_current_floor()
	return "Going to floor %d (%s, %s)." % [run.floor_number, run.get_department_id(),
		"boss floor" if run.is_boss_floor else "floor %d" % run.floor_in_department]


## The departments a run with this seed visits, in order: every DepartmentData in the rotation,
## sorted by order_hint (ties shuffled by the seed), at most Config.game.departments_per_run.
func department_order(run_seed: int) -> Array[StringName]:
	var departments: Array[DepartmentData] = []
	for content: ContentData in ContentRegistry.get_all(&"department"):
		var department := content as DepartmentData
		if department != null and department.in_run_rotation:
			departments.append(department)
	if departments.is_empty():
		return [PLACEHOLDER_DEPARTMENT_ID] as Array[StringName]
	# Shuffle first (seeded), then a stable sort by order_hint keeps the shuffle inside each tie.
	var rng: RandomNumberGenerator = SeededRng.make(run_seed, &"department_order")
	for index: int in range(departments.size() - 1, 0, -1):
		var other: int = rng.randi_range(0, index)
		var swap: DepartmentData = departments[index]
		departments[index] = departments[other]
		departments[other] = swap
	var ids: Array[StringName] = []
	for hint: int in _sorted_hints(departments):
		for department: DepartmentData in departments:
			if department.order_hint == hint:
				ids.append(department.id)
	if _config.departments_per_run > 0 and ids.size() > _config.departments_per_run:
		ids.resize(_config.departments_per_run)
	return ids


## A department by id (the placeholder too). Null if there is no such department.
func get_department(department_id: StringName) -> DepartmentData:
	if department_id == PLACEHOLDER_DEPARTMENT_ID:
		return _placeholder_department()
	return ContentRegistry.get_content(department_id) as DepartmentData


## Regular floors before a department's boss floor: its floor_count, or Config.game's
## floors_per_department if the department doesn't set one.
func floors_in(department: DepartmentData) -> int:
	if department == null:
		return 0
	return department.floor_count if department.floor_count > 0 else _config.floors_per_department


## Every floor in the run, boss floors included.
func total_floors(run: RunState) -> int:
	var total: int = 0
	for id: StringName in run.department_ids:
		total += floors_in(get_department(id)) + 1
	return total


## Moves a run to the given floor of the whole run. False if the run has fewer floors.
func place_on_floor(run: RunState, floor_number: int) -> bool:
	var left: int = floor_number
	for index: int in run.department_ids.size():
		var floors: int = floors_in(get_department(run.department_ids[index])) + 1
		if left <= floors:
			run.floor_number = floor_number
			run.department_index = index
			run.floor_in_department = left
			run.is_boss_floor = left == floors
			return true
		left -= floors
	return false


# --- Host: moving through the run ---------------------------------------------------------------

## Host: the next floor after a lift ride: the next regular floor, or this department's boss floor.
func _next_floor() -> void:
	if _run == null or _run.is_boss_floor:
		return
	place_on_floor(_run, _run.floor_number + 1)
	_load_current_floor()


## Host: the boss is down: the next department's first floor, or the run is won.
func _after_boss() -> void:
	if _run == null or not _run.is_boss_floor:
		return
	if _run.department_index + 1 >= _run.department_ids.size():
		end_run(RESULT_ESCAPED)
		return
	place_on_floor(_run, _run.floor_number + 1)
	_load_current_floor()


## Host: every PC goes to the floor in _run; it starts once they have all built it.
func _load_current_floor() -> void:
	if not _net.is_host() or _run == null:
		return
	# level_gen makes the layout here, on the host; it travels with the run to every PC.
	var department: DepartmentData = get_current_department()
	var layout: FloorLayout
	if _run.is_boss_floor:
		layout = LevelGenerator.generate_boss_floor(department, _run.floor_number, _run.run_seed, _config)
	else:
		layout = LevelGenerator.generate(department, _run.floor_in_department, _run.floor_number, _run.run_seed,
			_net.get_player_count(), _config)
	var data: Dictionary = _run.to_dict()
	data["layout"] = layout.to_dict()
	_transition(FLOOR_SCENE, data)


## Host: move everyone to a scene, in an order that never sends anyone updates for things they
## don't have (Godot prints errors for those):
## 1. every PC stops sending player updates, and the host leaves the old scene for a loading screen
##    (its bodies and props are removed on every PC while they all still have the old scene);
## 2. a moment later the clients load the new scene and report back;
## 3. when they all have it (or after floor_load_timeout), the host loads it too, so anything it
##    spawns there reaches PCs that already have the scene. Floors then start (floor_ready).
func _transition(path: String, run_data: Dictionary) -> void:
	_transition_id += 1
	var id: int = _transition_id
	_moving = true
	_built_peers.clear()
	_prepare_rpc.rpc()
	await get_tree().create_timer(CLIENT_LOAD_DELAY).timeout
	if id != _transition_id:
		return
	_load_scene.call(LOADING_SCENE)
	await get_tree().create_timer(CLIENT_LOAD_DELAY).timeout
	if id != _transition_id:
		return
	_transition_peers = multiplayer.get_peers()
	_load_rpc.rpc(path, run_data, id)
	var waited: float = 0.0
	var told: bool = false
	while not _all_built() and waited < _config.floor_load_timeout:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if id != _transition_id:
			return
		if not told and waited > SLOW_LOAD_NOTICE_SECONDS:
			told = true
			EventBus.toast_requested.emit("Waiting for %s to finish loading..." % ", ".join(_still_loading()))
	if not _all_built():
		push_warning("GameFlow: not every PC loaded '%s' in time; going on without them." % path.get_file())
	await _arrive(path, run_data)
	await get_tree().process_frame
	await get_tree().process_frame
	if id != _transition_id:
		return
	_moving = false
	if path == FLOOR_SCENE:
		_floor_ready_rpc.rpc()


## Host: names of the players whose PC hasn't loaded the new scene yet.
func _still_loading() -> PackedStringArray:
	var names: PackedStringArray = []
	var connected: PackedInt32Array = multiplayer.get_peers()
	for peer_id: int in _transition_peers:
		if connected.has(peer_id) and not _built_peers.has(peer_id):
			names.append(_net.get_display_name(_net.get_player_id_for_peer(peer_id)))
	return names


## Host: true when every client has loaded the scene of the current transition.
func _all_built() -> bool:
	var connected: PackedInt32Array = multiplayer.get_peers()
	for peer_id: int in _transition_peers:
		if connected.has(peer_id) and not _built_peers.has(peer_id):
			return false
	return true


## Every PC, about to change scene: stop sending player updates (see _transition).
@rpc("authority", "call_local", "reliable")
func _prepare_rpc() -> void:
	for node: Node in get_tree().get_nodes_in_group(PlayerCharacter.GROUP):
		var body := node as PlayerCharacter
		if body != null:
			body.stop_syncing()


## Host -> clients: load this scene, then say so.
@rpc("authority", "call_remote", "reliable")
func _load_rpc(path: String, run_data: Dictionary, id: int) -> void:
	_synced_from_host = true
	await _arrive(path, run_data)
	# Let the new scene finish its _ready (its spawners must exist before the host spawns things).
	await get_tree().process_frame
	await get_tree().process_frame
	_built_rpc.rpc_id(1, id)


@rpc("any_peer", "call_remote", "reliable")
func _built_rpc(id: int) -> void:
	if _net.is_host() and id == _transition_id:
		_built_peers[multiplayer.get_remote_sender_id()] = true


## This PC goes to a scene: the Break Room, or a floor (with the run it belongs to).
func _arrive(path: String, run_data: Dictionary) -> void:
	if path == BREAK_ROOM_SCENE:
		_enter_break_room()
		return
	_run = RunState.from_dict(run_data)
	_set_state(State.LOADING_FLOOR)
	EventBus.floor_loading.emit(_run.floor_number, _run.get_department_id())
	await _load_floor(run_data.get("layout", {}))


## Loads the floor scene and builds the floor in it (level_gen).
func _load_floor(layout_data: Dictionary) -> void:
	_layout_data = layout_data
	var old_scene: Node = get_tree().current_scene
	_load_scene.call(FLOOR_SCENE)
	# The scene change happens over the next frame or two: wait until the NEW floor scene is there.
	# (Going floor to floor, the old scene has the same file, so check it's a different node. Tests use
	# a fake scene changer, so give up waiting after a few frames.)
	for frame: int in SCENE_WAIT_FRAMES:
		await get_tree().process_frame
		var current: Node = get_tree().current_scene
		if current != null and current != old_scene and current.scene_file_path == FLOOR_SCENE:
			break
	_build_floor.call(FloorLayout.from_dict(_layout_data))

# --- RPCs (host -> everyone) --------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _run_started_rpc(run_data: Dictionary) -> void:
	_run = RunState.from_dict(run_data)
	_synced_from_host = true
	EventBus.run_started.emit(_run.run_seed)


@rpc("authority", "call_local", "reliable")
func _state_rpc(new_state: int) -> void:
	_set_state(new_state as State)


@rpc("authority", "call_local", "reliable")
func _floor_ready_rpc() -> void:
	if _run == null:
		return
	_set_state(State.BOSS_FIGHT if _run.is_boss_floor else State.ON_FLOOR)
	EventBus.floor_ready.emit(_run.floor_number, _run.get_department_id())
	if _run.is_boss_floor:
		var department: DepartmentData = get_current_department()
		EventBus.boss_floor_started.emit(department.boss_id if department != null else &"")


@rpc("authority", "call_local", "reliable")
func _run_ended_rpc(result: StringName) -> void:
	_set_state(State.RUN_SUMMARY)
	EventBus.run_ended.emit(result)


# --- Joining (with net_core's handshake) -----------------------------------------------------------

## Host: what a joining PC needs before Godot sends it anything (Net.set_join_handlers).
func _join_info() -> Dictionary:
	if _state in [State.BOOT, State.MAIN_MENU]:
		return {}
	return {"state": int(_state), "run": _run.to_dict() if _run != null else {}, "layout": _layout_data}


## Joining PC, before the connection opens: go to the host's scene (on a floor, you spectate
## until the next one). Net waits for this, so the host's players and props arrive into that scene.
func _prepare_for_join(info: Dictionary) -> void:
	if info.is_empty():
		return
	_synced_from_host = true
	var state: int = int(info.get("state", State.BREAK_ROOM))
	var run_data: Dictionary = info.get("run", {})
	if run_data.is_empty():
		_enter_break_room()
	else:
		await _join_run(state, run_data, info.get("layout", {}))
	await get_tree().process_frame
	await get_tree().process_frame


func _join_run(state: int, run_data: Dictionary, layout_data: Dictionary) -> void:
	_run = RunState.from_dict(run_data)
	EventBus.run_started.emit(_run.run_seed)
	match state as State:
		State.LOADING_FLOOR, State.ON_FLOOR, State.BOSS_FIGHT:
			_set_state(state as State)
			await _load_floor(layout_data)
			if state != State.LOADING_FLOOR:
				EventBus.floor_ready.emit(_run.floor_number, _run.get_department_id())
		State.RUN_SUMMARY:
			_set_state(State.RUN_SUMMARY)
			await _load_floor(layout_data)
		_:
			# The elevator ride: the host is still in the Break Room.
			_load_scene.call(BREAK_ROOM_SCENE)
			_set_state(state as State)


# --- Local helpers ------------------------------------------------------------------------------

func _set_state(new_state: State) -> void:
	if new_state == _state:
		return
	var old: State = _state
	_state = new_state
	EventBus.game_state_changed.emit(old, new_state)


func _enter_break_room() -> void:
	_run = null
	_set_state(State.BREAK_ROOM)
	var current: Node = get_tree().current_scene
	if current == null or current.scene_file_path != BREAK_ROOM_SCENE:
		_load_scene.call(BREAK_ROOM_SCENE)


func _drop_run_locally() -> void:
	if _run != null:
		_run = null
		EventBus.run_ended.emit(RESULT_ABANDONED)


## The game started in the main menu or the Break Room (not a test scene): GameFlow is in charge.
func _take_charge_of_start_scene() -> void:
	var current: Node = get_tree().current_scene
	var path: String = current.scene_file_path if current != null else ""
	if path == MAIN_MENU_SCENE:
		_set_state(State.MAIN_MENU)
	elif path == BREAK_ROOM_SCENE:
		_set_state(State.BREAK_ROOM)


func _placeholder_department() -> DepartmentData:
	if _placeholder == null:
		_placeholder = DepartmentData.new()
		_placeholder.id = PLACEHOLDER_DEPARTMENT_ID
		_placeholder.display_name = "Placeholder department"
		_placeholder.floor_count = _config.floors_per_department
		# One part to fetch per floor (Zachary, 2026-10-18), using the only lift part prop there is so far.
		_placeholder.lift_parts_per_floor = 1
		_placeholder.lift_part_prop_id = PLACEHOLDER_LIFT_PART_ID
	return _placeholder


static func _sorted_hints(departments: Array[DepartmentData]) -> Array[int]:
	var hints: Array[int] = []
	for department: DepartmentData in departments:
		if not hints.has(department.order_hint):
			hints.append(department.order_hint)
	hints.sort()
	return hints


func _first_floor_of(run: RunState, department_index: int) -> int:
	var floor_number: int = 1
	for index: int in department_index:
		floor_number += floors_in(get_department(run.department_ids[index])) + 1
	return floor_number


func _process(_delta: float) -> void:
	# The connection changed. Solo -> hosting keeps the run (the host still owns it); joining
	# someone, or losing the host, ends the run we had here.
	if multiplayer.multiplayer_peer != _peer_seen:
		_peer_seen = multiplayer.multiplayer_peer
		var host_now: bool = _net.is_host()
		if not _was_host or not host_now:
			_synced_from_host = false
			_drop_run_locally()
		_was_host = host_now


# --- EventBus -----------------------------------------------------------------------------------

func _on_elevator_start_accepted() -> void:
	if _net.is_host() and _state == State.BREAK_ROOM:
		start_run()


func _on_lift_departed(_floor_number: int) -> void:
	# Ignore a second press while everyone is already on the way (two players pressing at once).
	if _net.is_host() and _state == State.ON_FLOOR and not _moving:
		_next_floor()


func _on_boss_defeated(_boss_id: StringName) -> void:
	if _net.is_host() and _state == State.BOSS_FIGHT and not _moving:
		_after_boss()


func _on_team_wiped() -> void:
	if _net.is_host() and _state in [State.ON_FLOOR, State.BOSS_FIGHT, State.LOADING_FLOOR]:
		end_run(RESULT_WIPED)



# --- Console ------------------------------------------------------------------------------------

func _register_console_commands() -> void:
	DebugConsole.register_command(&"seed", _cmd_seed, "seed: the current run's seed and floor", false)
	DebugConsole.register_command(&"floor", _cmd_floor,
		"floor <n> [department_id]: jump to floor n (of the run, or of that department)")
	DebugConsole.register_command(&"end_run", _cmd_end_run, "end_run [escaped|wiped|abandoned]: end the run now")
	DebugConsole.register_command(&"flow", _cmd_flow, "flow: game_flow's state and run", false)


func _cmd_seed(_args: PackedStringArray, _player_id: int) -> String:
	if _run == null:
		return "No run in progress."
	return "Run seed %d | floor %d" % [_run.run_seed, _run.floor_number]


func _cmd_floor(args: PackedStringArray, _player_id: int) -> String:
	if args.is_empty() or not args[0].is_valid_int():
		return "Usage: floor <n> [department_id]"
	return debug_go_to_floor(args[0].to_int(), StringName(args[1]) if args.size() > 1 else &"")


func _cmd_end_run(args: PackedStringArray, _player_id: int) -> String:
	if _run == null:
		return "No run in progress."
	var result := StringName(args[0]) if not args.is_empty() else RESULT_ABANDONED
	end_run(result)
	return "Run ended (%s)." % result


func _cmd_flow(_args: PackedStringArray, _player_id: int) -> String:
	return describe()


## One line about the state and the run (for the console and test scenes).
func describe() -> String:
	var text: String = "State: %s" % get_state_name()
	if _run != null:
		text += " | seed %d | floor %d of %d | %s %s | departments: %s" % [_run.run_seed, _run.floor_number,
			total_floors(_run), _run.get_department_id(),
			"boss floor" if _run.is_boss_floor else "floor %d" % _run.floor_in_department,
			", ".join(_run.department_ids)]
	return text
