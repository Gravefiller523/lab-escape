class_name GameFlowService
extends Node
## Autoload "GameFlow". The game's big state machine: main menu, Break Room, lift rides, floors,
## boss fights and the run summary. It owns the run (seed, floor number, department order).
## Spec: docs/systems/game_flow.md.
##
## CHANGED 2026-10-19: from the Break Room to the end of a run, one scene stays loaded: the game world
## (game_world.tscn) with the cargo lift in it. The levels (the Break Room, then each floor) are loaded
## and unloaded around the lift while it rides, so everything inside it rides along. A ride: the lift
## leaves (cargo_lift emits lift_departed), every PC swaps the level, and once every PC has built it
## and the ride has lasted lift_ride_seconds, the lift arrives (floor_ready) and opens.
##
## The host decides every change and tells the clients (reliable RPCs). GameFlow only takes charge
## once it has loaded the main menu or the game world (or the game started in one); in a system's own
## test scene it stays out of the way, so test scenes and GUT tests are left alone.
##
## STUB until department content exists: runs use one placeholder department.

enum State { BOOT, MAIN_MENU, BREAK_ROOM, ELEVATOR_RIDE, LOADING_FLOOR, ON_FLOOR, BOSS_FIGHT, RUN_SUMMARY }

const MAIN_MENU_SCENE: String = "res://systems/ui/main_menu_background.tscn"
## The scene that stays loaded from the Break Room to the end of a run.
const WORLD_SCENE: String = "res://systems/game_flow/game_world.tscn"
## The Break Room level, loaded into the game world around the lift.
const BREAK_ROOM_SCENE: String = "res://systems/break_room/break_room.tscn"
## STUB (department content): used when no DepartmentData is in the run rotation.
const PLACEHOLDER_DEPARTMENT_ID: StringName = &"department_placeholder"
## STUB (department content): the placeholder department's lift part.
const PLACEHOLDER_LIFT_PART_ID: StringName = &"prop_lift_part_zoology"

const RESULT_ESCAPED: StringName = &"escaped"
const RESULT_WIPED: StringName = &"wiped"
const RESULT_ABANDONED: StringName = &"abandoned"
## Level kinds (the "kind" of a level dictionary).
const LEVEL_BREAK_ROOM: String = "break_room"
const LEVEL_FLOOR: String = "floor"
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
## How a level is put in the game world: func(level: Dictionary) -> void. Tests swap in a fake.
var _build_level: Callable
## The current (or, during a ride, the next) level: {"kind": ..., "layout": ...}. Sent to joiners.
var _level_data: Dictionary = {}
var _state: State = State.BOOT
var _run: RunState
var _last_result: StringName = &""
var _placeholder: DepartmentData
## Host: clients that have built the level of the current ride.
var _built_peers: Dictionary[int, bool] = {}
## Host: the clients a ride is waiting for (players who join during it build the new level as they join).
var _transition_peers: PackedInt32Array = []
## Host: a ride is under way (a second press can't start another one).
var _moving: bool = false
var _ride_id: int = 0
## Client: the host has told us where the game is (so a late "go to the Break Room" is ignored).
var _synced_from_host: bool = false
var _peer_seen: MultiplayerPeer
var _was_host: bool = true


## For tests only: a different Net and config, a fake scene changer and level builder. Call before
## adding to the tree.
func use_test_setup(net: NetService, config: GameConfig, scene_loader: Callable,
		level_builder: Callable = Callable()) -> void:
	_net = net
	_config = config
	_load_scene = scene_loader
	_build_level = level_builder if level_builder.is_valid() else func(_level: Dictionary) -> void: pass


func _ready() -> void:
	if _net == null:
		_net = Net
	if _config == null:
		_config = Config.game
	if not _load_scene.is_valid():
		_load_scene = func(path: String) -> void: get_tree().change_scene_to_file(path)
	if not _build_level.is_valid():
		_build_level = _build_level_in_world
	_peer_seen = multiplayer.multiplayer_peer
	EventBus.elevator_start_accepted.connect(_on_lift_departed.bind(0))
	EventBus.lift_departed.connect(_on_lift_departed)
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


## NEW 2026-10-19: how the last run ended (&"" before the first one). The Break Room's whiteboard shows it.
func get_last_run_result() -> StringName:
	return _last_result


## Host: start a run from the Break Room (the lift is leaving). 0 = a random seed (or debug_run_seed).
func start_run(run_seed: int = 0) -> void:
	if not _net.is_host() or is_in_run():
		return
	var run := RunState.new()
	run.run_seed = run_seed
	if run.run_seed == 0:
		run.run_seed = _config.debug_run_seed if _config.debug_run_seed != 0 else randi_range(1, 2147483646)
	run.department_ids = department_order(run.run_seed)
	place_on_floor(run, 1)
	_run_started_rpc.rpc(run.to_dict())
	_state_rpc.rpc(State.ELEVATOR_RIDE)
	_ride_to(_floor_level())


## Host: end the run. result: &"escaped", &"wiped" or &"abandoned". The lift takes everyone back down
## to the Break Room (players outside it are brought in first).
func end_run(result: StringName) -> void:
	if not _net.is_host() or not is_in_run() or _state == State.RUN_SUMMARY:
		return
	_run_ended_rpc.rpc(result)
	var lift: CargoLift = CargoLift.current()
	if lift != null:
		lift.gather_players()
	_ride_to({"kind": LEVEL_BREAK_ROOM})


## Host (and solo): go to the game world's Break Room from the menu. A client calls it after joining;
## it only does something there if the host hasn't already said where the game is.
func go_to_break_room() -> void:
	if _net.is_online() and not _net.is_host():
		if not _synced_from_host:
			_enter_world({"kind": LEVEL_BREAK_ROOM})
		return
	if _state in [State.BOOT, State.MAIN_MENU]:
		_host_enter_world()


## Local: leave the lobby (or the solo game) and go back to the main menu.
func return_to_main_menu() -> void:
	SteamSession.leave_lobby()
	_drop_run_locally()
	_level_data = {}
	_set_state(State.MAIN_MENU)
	_load_scene.call(MAIN_MENU_SCENE)


## Host, cheats only: jump to a floor (everyone is brought into the lift and it rides there). Without
## a department, floor_number counts across the whole run; with one, it is the floor inside that
## department (floor_count + 1 = its boss floor).
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
	var lift: CargoLift = CargoLift.current()
	if lift != null:
		lift.gather_players()
	_ride_to(_floor_level())
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

## Host: the lift left: start the run (Break Room), the next floor, or, after a boss, the next
## department (or the run is won).
func _on_lift_departed(_floor_number: int) -> void:
	# Ignore a second press while everyone is already on the way (two players pressing at once).
	if not _net.is_host() or _moving:
		return
	match _state:
		State.BREAK_ROOM:
			start_run()
		State.ON_FLOOR:
			if _run != null and not _run.is_boss_floor:
				place_on_floor(_run, _run.floor_number + 1)
				_ride_to(_floor_level())
		State.BOSS_FIGHT:
			if _run == null:
				return
			if _run.department_index + 1 >= _run.department_ids.size():
				end_run(RESULT_ESCAPED)
			else:
				place_on_floor(_run, _run.floor_number + 1)
				_ride_to(_floor_level())


## Host: the level for the current floor of the run (level_gen makes its layout here).
func _floor_level() -> Dictionary:
	var department: DepartmentData = get_current_department()
	var layout: FloorLayout
	if _run.is_boss_floor:
		layout = LevelGenerator.generate_boss_floor(department, _run.floor_number, _run.run_seed, _config)
	else:
		layout = LevelGenerator.generate(department, _run.floor_in_department, _run.floor_number, _run.run_seed,
			_net.get_player_count(), _config)
	return {"kind": LEVEL_FLOOR, "run": _run.to_dict(), "layout": layout.to_dict()}


## Host: the lift rides to a level. Props outside the lift are lost; every PC swaps the level while
## it rides; it arrives once every PC has built the level and the ride has lasted lift_ride_seconds.
func _ride_to(level: Dictionary) -> void:
	_ride_id += 1
	var id: int = _ride_id
	_moving = true
	var lift: CargoLift = CargoLift.current()
	if lift != null:
		lift.depart_now()
	_drop_props_outside_lift()
	_built_peers.clear()
	_transition_peers = multiplayer.get_peers()
	_level_rpc.rpc(level, id)
	var told: bool = false
	# Game time, not the wall clock, so the ride is the same length however fast frames come.
	var waited: float = 0.0
	while true:
		await get_tree().process_frame
		if id != _ride_id:
			return
		waited += get_process_delta_time()
		var ride_done: bool = waited >= _config.lift_ride_seconds
		if ride_done and (_all_built() or waited >= _config.lift_ride_seconds + _config.floor_load_timeout):
			break
		if not told and ride_done and waited > _config.lift_ride_seconds + SLOW_LOAD_NOTICE_SECONDS:
			told = true
			EventBus.toast_requested.emit("Waiting for %s to finish loading..." % ", ".join(_still_loading()))
	if not _all_built():
		push_warning("GameFlow: not every PC built the next level in time; arriving anyway.")
	_moving = false
	_host_arrive(level)


## Host: the lift is there. Tell the lift (parts to find, Break Room, boss) and then everyone.
func _host_arrive(level: Dictionary) -> void:
	var world: GameWorld = GameWorld.current()
	var lift: CargoLift = CargoLift.current()
	var to_break_room: bool = str(level.get("kind", "")) == LEVEL_BREAK_ROOM
	if lift != null:
		if to_break_room:
			lift.arrive(0, true)
		elif _run != null and _run.is_boss_floor:
			lift.arrive(0, false, true)
		else:
			var department: DepartmentData = get_current_department()
			lift.arrive(department.lift_parts_per_floor if department != null else 1, false)
	if world != null:
		# Players who join from now on (or waited for this floor) appear here.
		world.get_player_spawner().spawn_points = _spawn_points_for(level, world)
	_arrived_rpc.rpc(level)


## Host: drops props that are not in the lift (they stay behind with the old level).
func _drop_props_outside_lift() -> void:
	var lift: CargoLift = CargoLift.current()
	var world: GameWorld = GameWorld.current()
	if lift == null or world == null:
		return
	var keep: Array[NetProp] = lift.get_zone().get_props_inside()
	for prop: NetProp in world.get_prop_spawner().get_props():
		if not keep.has(prop) and not prop.is_held():
			world.get_prop_spawner().despawn(prop)


## Host: names of the players whose PC hasn't built the new level yet.
func _still_loading() -> PackedStringArray:
	var names: PackedStringArray = []
	var connected: PackedInt32Array = multiplayer.get_peers()
	for peer_id: int in _transition_peers:
		if connected.has(peer_id) and not _built_peers.has(peer_id):
			names.append(_net.get_display_name(_net.get_player_id_for_peer(peer_id)))
	return names


## Host: true when every client has built the level of the current ride.
func _all_built() -> bool:
	var connected: PackedInt32Array = multiplayer.get_peers()
	for peer_id: int in _transition_peers:
		if connected.has(peer_id) and not _built_peers.has(peer_id):
			return false
	return true


## Host: go from the menu into the game world and its Break Room. Players usually join once it is
## there (the join handshake loads it for them); anyone already connected is brought along first,
## and players only appear once every PC has the world.
func _host_enter_world() -> void:
	var level: Dictionary = {"kind": LEVEL_BREAK_ROOM}
	_ride_id += 1
	var id: int = _ride_id
	await _enter_world(level)
	_built_peers.clear()
	_transition_peers = multiplayer.get_peers()
	if not _transition_peers.is_empty():
		_world_rpc.rpc(level, id)
		var started_msec: int = Time.get_ticks_msec()
		while not _all_built() and Time.get_ticks_msec() - started_msec < int(_config.floor_load_timeout * 1000.0):
			await get_tree().process_frame
		if id != _ride_id:
			return
	var world: GameWorld = GameWorld.current()
	if world != null:
		var spawner: PlayerSpawner = world.get_player_spawner()
		spawner.spawn_points = _spawn_points_for(level, world)
		spawner.spawn_all(spawner.spawn_points)
		spawner.auto_spawn = true
	var lift: CargoLift = CargoLift.current()
	if lift != null:
		lift.arrive(0, true)


## Where players appear in a level: the Break Room's spawn points, or inside the lift on floors.
func _spawn_points_for(level: Dictionary, world: GameWorld) -> Array[Node3D]:
	if str(level.get("kind", "")) == LEVEL_BREAK_ROOM:
		var room: BreakRoom = _break_room_in(world)
		if room != null:
			return room.get_spawn_points()
	return world.get_lift().get_spawn_points()


static func _break_room_in(world: GameWorld) -> BreakRoom:
	for child: Node in world.get_node("LevelRoot").get_children():
		if child is BreakRoom:
			return child as BreakRoom
	return null


# --- Every PC: the world and its levels ------------------------------------------------------------

## Loads the game world (if it isn't loaded) and puts a level in it.
func _enter_world(level: Dictionary) -> void:
	var current: Node = get_tree().current_scene
	if current == null or current.scene_file_path != WORLD_SCENE:
		var old_scene: Node = current
		_load_scene.call(WORLD_SCENE)
		# The scene change happens over the next frame or two (tests use a fake changer: give up waiting).
		for frame: int in SCENE_WAIT_FRAMES:
			await get_tree().process_frame
			var now: Node = get_tree().current_scene
			if now != null and now != old_scene and now.scene_file_path == WORLD_SCENE:
				break
	_show_level(level)
	if str(level.get("kind", "")) == LEVEL_BREAK_ROOM:
		_run = null
		_set_state(State.BREAK_ROOM)


## Builds a level here and remembers it (for joiners).
func _show_level(level: Dictionary) -> void:
	_level_data = level
	_build_level.call(level)


## The real level builder: the Break Room scene, or a floor from its layout, in the game world.
func _build_level_in_world(level: Dictionary) -> void:
	var world: GameWorld = GameWorld.current()
	if world == null:
		return
	if str(level.get("kind", "")) == LEVEL_BREAK_ROOM:
		world.build_break_room(load(BREAK_ROOM_SCENE) as PackedScene)
	else:
		var layout_data: Dictionary = level.get("layout", {})
		world.build_floor(FloorLayout.from_dict(layout_data))


# --- RPCs (host -> everyone) --------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _run_started_rpc(run_data: Dictionary) -> void:
	_run = RunState.from_dict(run_data)
	_synced_from_host = true
	EventBus.run_started.emit(_run.run_seed)


@rpc("authority", "call_local", "reliable")
func _state_rpc(new_state: int) -> void:
	_set_state(new_state as State)


## Host -> everyone, while the lift rides: swap to this level, then (clients) say it's built.
@rpc("authority", "call_local", "reliable")
func _level_rpc(level: Dictionary, id: int) -> void:
	_synced_from_host = true
	if str(level.get("kind", "")) == LEVEL_FLOOR:
		var run_data: Dictionary = level.get("run", {})
		_run = RunState.from_dict(run_data)
		_set_state(State.LOADING_FLOOR)
		EventBus.floor_loading.emit(_run.floor_number, _run.get_department_id())
	_show_level(level)
	if multiplayer.is_server():
		return
	# Let the new level finish its _ready, then tell the host.
	await get_tree().process_frame
	await get_tree().process_frame
	_built_rpc.rpc_id(1, id)


## Host -> clients already connected: come into the game world too (see _host_enter_world).
@rpc("authority", "call_remote", "reliable")
func _world_rpc(level: Dictionary, id: int) -> void:
	_synced_from_host = true
	await _enter_world(level)
	await get_tree().process_frame
	await get_tree().process_frame
	_built_rpc.rpc_id(1, id)


@rpc("any_peer", "call_remote", "reliable")
func _built_rpc(id: int) -> void:
	if _net.is_host() and id == _ride_id:
		_built_peers[multiplayer.get_remote_sender_id()] = true


## Host -> everyone: the lift has arrived at the level (it opens its own doors).
@rpc("authority", "call_local", "reliable")
func _arrived_rpc(level: Dictionary) -> void:
	if str(level.get("kind", "")) == LEVEL_BREAK_ROOM:
		_run = null
		_set_state(State.BREAK_ROOM)
		return
	if _run == null:
		return
	_set_state(State.BOSS_FIGHT if _run.is_boss_floor else State.ON_FLOOR)
	EventBus.floor_ready.emit(_run.floor_number, _run.get_department_id())
	if _run.is_boss_floor:
		var department: DepartmentData = get_current_department()
		EventBus.boss_floor_started.emit(department.boss_id if department != null else &"")


@rpc("authority", "call_local", "reliable")
func _run_ended_rpc(result: StringName) -> void:
	_last_result = result
	_set_state(State.RUN_SUMMARY)
	EventBus.run_ended.emit(result)


# --- Joining (with net_core's handshake) -----------------------------------------------------------

## Host: what a joining PC needs before Godot sends it anything (Net.set_join_handlers).
func _join_info() -> Dictionary:
	if _state in [State.BOOT, State.MAIN_MENU] or _level_data.is_empty():
		return {}
	return {"state": int(_state), "run": _run.to_dict() if _run != null else {}, "level": _level_data}


## Joining PC, before the connection opens: load the game world and the host's level (on a floor, you
## spectate until the next one). Net waits for this, so the host's players and props arrive into it.
func _prepare_for_join(info: Dictionary) -> void:
	if info.is_empty():
		return
	_synced_from_host = true
	var state: int = info.get("state", State.BREAK_ROOM)
	var run_data: Dictionary = info.get("run", {})
	var level: Dictionary = info.get("level", {"kind": LEVEL_BREAK_ROOM})
	if not run_data.is_empty():
		_run = RunState.from_dict(run_data)
		EventBus.run_started.emit(_run.run_seed)
	await _enter_world(level)
	if not run_data.is_empty():
		_set_state(state as State)
		if state == State.ON_FLOOR or state == State.BOSS_FIGHT:
			EventBus.floor_ready.emit(_run.floor_number, _run.get_department_id())
	await get_tree().process_frame
	await get_tree().process_frame


# --- Local helpers ------------------------------------------------------------------------------

func _set_state(new_state: State) -> void:
	if new_state == _state:
		return
	var old: State = _state
	_state = new_state
	EventBus.game_state_changed.emit(old, new_state)


func _drop_run_locally() -> void:
	if _run != null:
		_run = null
		EventBus.run_ended.emit(RESULT_ABANDONED)


## The game started in the main menu (not a test scene): GameFlow is in charge.
func _take_charge_of_start_scene() -> void:
	var current: Node = get_tree().current_scene
	var path: String = current.scene_file_path if current != null else ""
	if path == MAIN_MENU_SCENE:
		_set_state(State.MAIN_MENU)


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
