extends Node
## Plays a whole run inside a real game process (NEW 2026-11-11, roadmap WP1). tests/integration/test_full_run.gd
## starts one host and some clients as separate Godot processes running full_run_launcher.tscn; each gets a
## driver (this script) under the scene tree's root, so it survives GameFlow's scene changes. Only public APIs
## are used, the same calls the UI, the lift button and the printer make.
##
## Host: hosts locally, waits for the clients in the Break Room, starts the run, and on every floor fixes the
## lift (moves each broken slot's part into its socket), kills and reprints a client on the death floor, waits
## for the late joiner on the late floor, beats the boss on boss floors, and presses Go. Clients: join and
## write down every floor they reach, whether they have a body there, and how the run ended.
## Each process writes a JSON report to --out (and the host its progress to --progress), then quits.
##
## NEW (roadmap WP2): a "leaver" client grabs a lift part the host puts in front of it and quits the game on the
## leave floor; the host can also walk out mid-floor (quit floor). Clients write down where they end up afterwards.
##
## Command line (after "--"): --role=host|client|leaver --port=N --out=PATH [--progress=PATH] [--seed=N]
## [--floors=N --boss_every=N --ride=SECONDS] (host: shortens the run) [--start_players=N] [--late_floor=N
## --late_players=N] [--death_floor=N] [--leave_floor=N --leaver_id_file=PATH] [--quit_floor=N]
## Leaver: --id_file=PATH --host_progress=PATH

const FLOOR_TIMEOUT: float = 90.0
const STEP_TIMEOUT: float = 20.0
const JOIN_TIMEOUT: float = 60.0
## Time on each floor before doing anything, so spawns and syncing settle.
const SETTLE_SECONDS: float = 1.0
## Clients look for their body this long after floor_ready (before the host does anything on the floor).
const CLIENT_SETTLE_SECONDS: float = 0.5
## Host: extra time on the death floor before the kill, so every client has written down its floor first.
const DEATH_DELAY_SECONDS: float = 2.0
## Host: time in the Break Room after the run, so clients see the end before the host leaves.
const LINGER_SECONDS: float = 4.0
## Every process gives up after this long and reports what it saw.
const TOTAL_TIMEOUT: float = 900.0
## Clients: how long after the host has gone they check where they ended up.
const HOST_GONE_SECONDS: float = 3.0

var _args: Dictionary[String, String] = {}
var _report: Dictionary = {"ok": false, "role": "", "floors": [], "notes": []}
var _finished: bool = false
var _boss_defeated: bool = false
var _run_result: StringName = &""


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.trim_prefix("--").split("=", true, 1)
		_args[parts[0]] = parts[1] if parts.size() > 1 else "true"
	_report["role"] = _arg("role", "host")
	EventBus.boss_defeated.connect(func(_boss_id: StringName) -> void: _boss_defeated = true)
	EventBus.run_ended.connect(func(result: StringName) -> void: _run_result = result)
	get_tree().create_timer(TOTAL_TIMEOUT).timeout.connect(func() -> void: _finish("timed out"))
	if _report["role"] == "host":
		_run_host()
	else:
		_run_client()


func _arg(key: String, default: String = "") -> String:
	return _args.get(key, default)


func _int_arg(key: String, default: int) -> int:
	return _arg(key, str(default)).to_int()


# --- Host -------------------------------------------------------------------------------------------------------

func _run_host() -> void:
	if _args.has("floors"):
		Config.game.run_floor_count = _int_arg("floors", Config.game.run_floor_count)
	if _args.has("boss_every"):
		Config.game.boss_every_floors = _int_arg("boss_every", Config.game.boss_every_floors)
	if _args.has("ride"):
		Config.game.lift_ride_seconds = _arg("ride").to_float()
	# A flat battery has to sit on the charger first; this run slots parts straight in.
	for prop: ContentData in ContentRegistry.get_all(&"prop"):
		var data := prop as PropData
		if data != null and data.needs_charge_seconds > 0.0:
			data.needs_charge_seconds = 0.0
	SteamSession.host_local(_int_arg("port", 18300))
	# The main menu's UI does this after hosting; this process never shows the menu.
	GameFlow.go_to_break_room()
	if not await _until(func() -> bool: return GameFlow.get_state() == GameFlowService.State.BREAK_ROOM, STEP_TIMEOUT):
		_finish("never reached the Break Room")
		return
	_progress("break_room")
	var start_players: int = _int_arg("start_players", 1)
	if not await _until(func() -> bool: return Net.get_player_count() >= start_players, JOIN_TIMEOUT):
		_note("only %d of %d players joined before the run" % [Net.get_player_count(), start_players])
	var start_ids: Array[int] = Net.get_player_ids()
	# Start the way players do: everyone into the lift, then Go (the host checks everyone is aboard).
	Config.game.debug_run_seed = _int_arg("seed", 4242)
	CargoLift.current().gather_players()
	if not await _press_go():
		_finish("the lift wouldn't leave the Break Room")
		return
	var total: int = Config.game.run_floor_count
	for floor_number: int in range(1, total + 1):
		var reached: bool = await _until(func() -> bool: return _on_floor(floor_number), FLOOR_TIMEOUT)
		if not reached:
			_finish("floor %d never started (state %s)" % [floor_number, GameFlow.get_state_name()])
			return
		await _seconds(SETTLE_SECONDS)
		var entry: Dictionary = _floor_entry(floor_number)
		_progress("floor_%d" % floor_number)
		if floor_number == _int_arg("late_floor", 0):
			entry["late_join"] = await _wait_for_late_joiner(start_ids)
		if floor_number == _int_arg("death_floor", 0):
			await _seconds(DEATH_DELAY_SECONDS)
			entry["death"] = await _kill_and_reprint(start_ids)
		if floor_number == _int_arg("leave_floor", 0):
			entry["leave"] = await _watch_leaver()
		if floor_number == _int_arg("quit_floor", 0):
			# The host walks out mid-floor: the clients must land back in the menu.
			(_report["floors"] as Array).append(entry)
			_report["ok"] = true
			_finish()
			return
		var run: RunState = GameFlow.get_run()
		if run.is_boss_floor:
			entry["boss"] = await _beat_boss()
		else:
			entry["lift_fixed"] = await _fix_lift()
		entry["departed"] = await _press_go()
		(_report["floors"] as Array).append(entry)
		if not entry["departed"]:
			_finish("the lift wouldn't leave floor %d" % floor_number)
			return
	await _until(func() -> bool: return _run_result != &"", FLOOR_TIMEOUT)
	_report["result"] = String(_run_result)
	await _until(func() -> bool: return GameFlow.get_state() == GameFlowService.State.BREAK_ROOM, FLOOR_TIMEOUT)
	_report["final_state"] = GameFlow.get_state_name()
	_progress("done")
	await _seconds(LINGER_SECONDS)
	_report["ok"] = true
	_finish()


func _on_floor(floor_number: int) -> bool:
	var run: RunState = GameFlow.get_run()
	return run != null and run.floor_number == floor_number and GameFlow.get_state() in [
		GameFlowService.State.ON_FLOOR, GameFlowService.State.BOSS_FIGHT]


func _floor_entry(floor_number: int) -> Dictionary:
	var run: RunState = GameFlow.get_run()
	var bodies: Array[int] = []
	var waiting: Array[int] = []
	for player_id: int in Net.get_player_ids():
		var body: PlayerCharacter = PlayerCharacter.find(player_id)
		if body != null and not body.is_ghost():
			bodies.append(player_id)
		if Net.is_waiting_for_next_floor(player_id):
			waiting.append(player_id)
	return {"floor": floor_number, "department": String(run.get_department_id()), "boss_floor": run.is_boss_floor,
		"players": Net.get_player_ids(), "bodies": bodies, "waiting": waiting,
		"enemies": Enemies.get_alive().size(),
		"printers": get_tree().get_nodes_in_group(Printer3D.GROUP).size(),
		"vendors": get_tree().get_nodes_in_group(Vendor.GROUP).size()}


## The late joiner connects while this floor is running: it must wait (a ghost camera, no body) until the next.
func _wait_for_late_joiner(start_ids: Array[int]) -> Dictionary:
	var wanted: int = _int_arg("late_players", start_ids.size() + 1)
	var joined: bool = await _until(func() -> bool: return Net.get_player_count() >= wanted, JOIN_TIMEOUT)
	var late_id: int = 0
	for player_id: int in Net.get_player_ids():
		if not start_ids.has(player_id):
			late_id = player_id
	await _seconds(SETTLE_SECONDS)
	return {"joined": joined, "player_id": late_id, "waiting": Net.is_waiting_for_next_floor(late_id),
		"has_body": PlayerCharacter.find(late_id) != null}


## Kills the first client (the host if alone), then reprints it in the lift the way the printer does.
func _kill_and_reprint(start_ids: Array[int]) -> Dictionary:
	var victim: int = Net.local_player_id()
	for player_id: int in start_ids:
		if player_id != Net.local_player_id():
			victim = player_id
			break
	Death.kill(victim)
	var died: bool = await _until(func() -> bool: return Death.is_dead(victim), STEP_TIMEOUT)
	var ghost: bool = PlayerCharacter.find(victim) != null and PlayerCharacter.find(victim).is_ghost()
	var spot: Transform3D = CargoLift.current().get_spawn_points()[0].global_transform
	Death.reprint(victim, spot)
	var is_back: Callable = func() -> bool:
		var body: PlayerCharacter = PlayerCharacter.find(victim)
		return not Death.is_dead(victim) and body != null and not body.is_ghost()
	var back: bool = await _until(is_back, STEP_TIMEOUT)
	return {"player_id": victim, "died": died, "ghost": ghost, "reprinted": back}


## NEW (roadmap WP2): the leaver (a client) is given a crowbar and grabs one of the lift's parts, then quits the game.
## Its crowbar must drop where it stood, and the part must stay on the floor, let go, so the lift can still be fixed.
func _watch_leaver() -> Dictionary:
	var leaver_id: int = _read_file(_arg("leaver_id_file")).to_int()
	var body: PlayerCharacter = PlayerCharacter.find(leaver_id)
	if body == null:
		return {"found": false}
	InventoryComponent.of(body).add_item(&"item_crowbar")
	var part: NetProp = null
	var lift: CargoLift = CargoLift.current()
	for slot: StringName in lift.get_broken_slots():
		var data: PropData = lift.get_slot_part(slot)
		for prop: NetProp in Props.get_props(data.id if data != null else &""):
			if not prop.needs_help():
				part = prop
	if part == null:
		return {"found": true, "part": false}
	var part_id: StringName = part.data.id
	part.global_position = body.global_position - body.global_transform.basis.z + Vector3.UP
	part.linear_velocity = Vector3.ZERO
	var crowbars_before: int = Props.get_props(&"item_crowbar").size()
	await _seconds(0.5)
	_progress("leave_now:%d" % part.net_id)
	var held_by_leaver: Callable = func() -> bool:
		return is_instance_valid(part) and part.get_holder_ids().has(leaver_id)
	var held: bool = await _until(held_by_leaver, STEP_TIMEOUT)
	var gone: bool = await _until(func() -> bool: return not Net.get_player_ids().has(leaver_id), JOIN_TIMEOUT)
	await _seconds(SETTLE_SECONDS)
	var still_there: bool = is_instance_valid(part) and not part.is_queued_for_deletion()
	return {"found": true, "part": true, "part_id": String(part_id), "held_by_leaver": held, "left": gone,
		"part_still_there": still_there, "part_let_go": still_there and not part.is_held(),
		"crowbar_dropped": Props.get_props(&"item_crowbar").size() > crowbars_before,
		"body_gone": PlayerCharacter.find(leaver_id) == null}


func _beat_boss() -> Dictionary:
	var found: bool = await _until(func() -> bool: return Boss.current() != null, STEP_TIMEOUT)
	if not found:
		return {"found": false}
	var boss: Boss = Boss.current()
	var boss_id: String = String(boss.data.id) if boss.data != null else ""
	var health: HealthComponent = HealthComponent.of(boss)
	health.apply_damage(DamageInfo.make(health.get_max() * 10.0, &"debug"))
	var defeated: bool = await _until(func() -> bool: return _boss_defeated, STEP_TIMEOUT)
	_boss_defeated = false
	return {"found": true, "boss_id": boss_id, "defeated": defeated}


## Moves each broken slot's part into its socket, as a player carrying it would.
func _fix_lift() -> bool:
	var lift: CargoLift = CargoLift.current()
	for slot: StringName in lift.get_broken_slots():
		var part: PropData = lift.get_slot_part(slot)
		var props: Array[NetProp] = Props.get_props(part.id) if part != null else ([] as Array[NetProp])
		if props.is_empty():
			_note("floor %d: no %s on the floor for the %s slot" % [GameFlow.get_run().floor_number, part.id if part != null else &"?", slot])
			continue
		var socket := lift.get_node_or_null("Slot_%s/Socket" % slot) as Node3D
		if socket == null:
			_note("lift has no socket for %s" % slot)
			continue
		props[0].global_position = socket.global_position + Vector3.UP * 0.2
		props[0].linear_velocity = Vector3.ZERO
		await _until(func() -> bool: return not lift.get_broken_slots().has(slot), STEP_TIMEOUT)
	return await _until(func() -> bool: return not lift.is_broken(), STEP_TIMEOUT)


func _press_go() -> bool:
	var lift: CargoLift = CargoLift.current()
	await _until(func() -> bool: return lift.depart_blocker().is_empty(), STEP_TIMEOUT)
	var blocker: String = lift.depart_blocker()
	if not blocker.is_empty():
		var run: RunState = GameFlow.get_run()
		_note("floor %d: Go blocked: %s" % [run.floor_number if run != null else 0, blocker])
		return false
	lift.request_depart()
	return await _until(func() -> bool: return lift.is_riding(), STEP_TIMEOUT)


# --- Clients ----------------------------------------------------------------------------------------------------

func _run_client() -> void:
	EventBus.floor_ready.connect(_on_client_floor_ready)
	SteamSession.connection_lost.connect(func() -> void: _note("connection lost"))
	SteamSession.lobby_joined.connect(func(_lobby_id: int) -> void: GameFlow.go_to_break_room())
	if _args.has("join_delay"):
		await _seconds(_arg("join_delay").to_float())
	SteamSession.join_local("127.0.0.1", _int_arg("port", 18300))
	var in_roster: Callable = func() -> bool:
		return Net.is_online() and Net.get_player_ids().has(Net.local_player_id())
	if not await _until(in_roster, JOIN_TIMEOUT):
		_finish("couldn't join")
		return
	_report["player_id"] = Net.local_player_id()
	_report["joined_in_state"] = GameFlow.get_state_name()
	_report["waiting_on_join"] = Net.is_waiting_for_next_floor(Net.local_player_id())
	if _report["role"] == "leaver":
		await _leave_holding_a_part()
		return
	await _until(func() -> bool: return _run_result != &"" or not Net.is_online(), TOTAL_TIMEOUT)
	_report["result"] = String(_run_result)
	var home_or_gone: Callable = func() -> bool:
		return GameFlow.get_state() == GameFlowService.State.BREAK_ROOM or not Net.is_online()
	await _until(home_or_gone, FLOOR_TIMEOUT)
	_report["final_state"] = GameFlow.get_state_name()
	# Stay until the host leaves, then see where that leaves us (the main menu, with a message).
	await _until(func() -> bool: return not Net.is_online(), FLOOR_TIMEOUT)
	_report["host_left"] = not Net.is_online()
	await _seconds(HOST_GONE_SECONDS)
	_report["state_after_host_left"] = GameFlow.get_state_name()
	_report["ok"] = _run_result != &"" or bool(_report["host_left"])
	_finish()


## The leaver: writes its id for the host, waits for the host to put a lift part in front of it, grabs it, and quits.
func _leave_holding_a_part() -> void:
	var id_file: FileAccess = FileAccess.open(_arg("id_file"), FileAccess.WRITE)
	if id_file != null:
		id_file.store_string(str(Net.local_player_id()))
		id_file.close()
	var host_progress: String = _arg("host_progress")
	if not await _until(func() -> bool: return _read_file(host_progress).begins_with("leave_now:"), TOTAL_TIMEOUT):
		_finish("the host never said when to leave")
		return
	var part: NetProp = Props.get_prop(_read_file(host_progress).trim_prefix("leave_now:").to_int())
	var body: PlayerCharacter = PlayerCharacter.find(Net.local_player_id())
	if part == null or body == null:
		_finish("no part (%s) or no body (%s)" % [part != null, body != null])
		return
	var grab: GrabController = PropsService.grab_of(body)
	grab.try_grab(part)
	_report["held"] = await _until(func() -> bool: return grab.get_held() == part and part.is_held(), STEP_TIMEOUT)
	_report["ok"] = true
	_finish()


func _on_client_floor_ready(floor_number: int, department_id: StringName) -> void:
	await _seconds(CLIENT_SETTLE_SECONDS)
	var body: PlayerCharacter = PlayerCharacter.find(Net.local_player_id())
	(_report["floors"] as Array).append({"floor": floor_number, "department": String(department_id),
		"has_body": body != null and not body.is_ghost(), "players": Net.get_player_ids()})


# --- Helpers ----------------------------------------------------------------------------------------------------

## Waits (in game time) until the check is true. False if it timed out.
func _until(check: Callable, timeout: float) -> bool:
	var waited: float = 0.0
	while not check.call():
		if waited >= timeout or _finished:
			return false
		await get_tree().process_frame
		waited += get_process_delta_time()
	return true


func _read_file(path: String) -> String:
	return FileAccess.get_file_as_string(path) if not path.is_empty() and FileAccess.file_exists(path) else ""


func _seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _note(text: String) -> void:
	print("[full_run] %s" % text)
	(_report["notes"] as Array).append(text)


func _progress(stage: String) -> void:
	print("[full_run] %s: %s" % [_report["role"], stage])
	var path: String = _arg("progress")
	if path.is_empty():
		return
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(stage)


func _finish(failure: String = "") -> void:
	if _finished:
		return
	_finished = true
	if not failure.is_empty():
		_report["ok"] = false
		_note(failure)
	var path: String = _arg("out")
	if not path.is_empty():
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(_report, "  "))
			file.close()
	print("[full_run] %s finished: %s" % [_report["role"], "ok" if _report["ok"] else "FAILED"])
	SteamSession.leave_lobby()
	get_tree().quit(0 if _report["ok"] else 1)
