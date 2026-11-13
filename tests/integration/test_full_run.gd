extends GutTest
## A whole run, Break Room to escape and back, with a host, a client and a late joiner (NEW 2026-11-11,
## roadmap WP1). Every PC is its own Godot process (the autoloads exist once per process, so this can't be done
## inside one), running tests/integration/full_run/full_run_launcher.tscn with local networking.
##
## The quick run (always): 4 floors with a boss every 2nd floor and 1 s lift rides. The late joiner connects while
## floor 1 is running, a client dies and is reprinted on floor 3, both bosses are beaten and the team escapes.
## The long run: set the environment variable LAB_ESCAPE_FULL_RUN=soak before running the tests to play the real
## run length from config/game_config.tres instead (12 floors since 2026-11-13; it was about 6 minutes for 18).
##
## Each process writes a JSON report and a log to user://full_run_test/ (see the Output panel for the folder).

const LAUNCHER: String = "res://tests/integration/full_run/full_run_launcher.tscn"
const PORT: int = 18311
const QUICK_FLOORS: int = 4
const QUICK_BOSS_EVERY: int = 2
const QUICK_RIDE_SECONDS: float = 1.0
const LATE_FLOOR: int = 1
const DEATH_FLOOR: int = 3
## Seconds to wait for the host to reach the late joiner's floor, and for everything to finish.
const START_TIMEOUT: float = 120.0
const QUICK_TIMEOUT: float = 300.0
const SOAK_TIMEOUT: float = 1200.0
## Lines in a log that are Godot's normal report when a process quits, not bugs.
const EXIT_NOISE: PackedStringArray = ["leaked at exit", "resources still in use at exit", "Pages in use exist at exit"]
## Known problems with a roadmap work package of their own. They are still printed in the test's output; delete a line
## here when its package fixes it.
const KNOWN: PackedStringArray = []
## The same, but only allowed after the process has finished its run and is leaving.
const KNOWN_WHILE_LEAVING: PackedStringArray = [
	# (empty since 2026-11-13: G51, the ENet error when the host left a local game, was fixed in roadmap WP15b)
]

var _dir: String = ""
var _pids: Dictionary[String, int] = {}


func before_all() -> void:
	_dir = ProjectSettings.globalize_path("user://full_run_test")
	DirAccess.make_dir_recursive_absolute(_dir)
	for file: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(file))
	gut.p("Full run reports and logs: %s" % _dir)


func after_all() -> void:
	for role: String in _pids:
		if OS.is_process_running(_pids[role]):
			OS.kill(_pids[role])


func _path(role: String, extension: String) -> String:
	return _dir.path_join("%s.%s" % [role, extension])


func _start(role: String, net_role: String, extra: PackedStringArray = PackedStringArray()) -> void:
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--log-file", _path(role, "log"), LAUNCHER, "--",
		"--role=%s" % net_role, "--port=%d" % PORT, "--out=%s" % _path(role, "json")])
	args.append_array(extra)
	_pids[role] = OS.create_process(OS.get_executable_path(), args)
	assert_gt(_pids[role], 0, "the %s process started" % role)


func _running(role: String) -> bool:
	return _pids.has(role) and OS.is_process_running(_pids[role])


func _read_text(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _report(role: String) -> Dictionary:
	var data: Variant = JSON.parse_string(_read_text(_path(role, "json")))
	return data as Dictionary if data is Dictionary else {}


## The lines in a process's log that are errors or warnings (Godot's quit report left out).
func _problems(role: String) -> PackedStringArray:
	var found := PackedStringArray()
	var leaving: bool = false
	for line: String in _read_text(_path(role, "log")).split("\n"):
		leaving = leaving or (line.begins_with("[full_run] ") and line.contains(" finished: "))
		if not (line.begins_with("SCRIPT ERROR") or line.begins_with("ERROR") or line.begins_with("WARNING")):
			continue
		var noise: bool = false
		for text: String in EXIT_NOISE:
			noise = noise or line.contains(text)
		var known: PackedStringArray = KNOWN + KNOWN_WHILE_LEAVING if leaving else KNOWN
		for text: String in known:
			if line.contains(text):
				noise = true
				gut.p("%s log (known, see the roadmap): %s" % [role, line.strip_edges()])
		if not noise:
			found.append(line.strip_edges())
	return found


func _floor_numbers(floors: Array) -> Array[int]:
	var numbers: Array[int] = []
	for entry: Variant in floors:
		numbers.append(int((entry as Dictionary).get("floor", 0)))
	return numbers


func test_a_whole_run_with_a_client_and_a_late_joiner() -> void:
	var soak: bool = OS.get_environment("LAB_ESCAPE_FULL_RUN") == "soak"
	var host_args := PackedStringArray(["--progress=%s" % _path("host", "progress"), "--start_players=2",
		"--late_floor=%d" % LATE_FLOOR, "--late_players=3", "--death_floor=%d" % DEATH_FLOOR])
	if not soak:
		host_args.append_array(["--floors=%d" % QUICK_FLOORS, "--boss_every=%d" % QUICK_BOSS_EVERY,
			"--ride=%s" % QUICK_RIDE_SECONDS])
	_start("host", "host", host_args)
	_start("client", "client")
	var at_late_floor: Callable = func() -> bool:
		return _read_text(_path("host", "progress")) == "floor_%d" % LATE_FLOOR or not _running("host")
	await wait_until(at_late_floor, START_TIMEOUT)
	assert_eq(_read_text(_path("host", "progress")), "floor_%d" % LATE_FLOOR, "the host reached the late join floor")
	_start("late", "client")
	var all_done: Callable = func() -> bool:
		return not _running("host") and not _running("client") and not _running("late")
	await wait_until(all_done, SOAK_TIMEOUT if soak else QUICK_TIMEOUT)

	var host: Dictionary = _report("host")
	var client: Dictionary = _report("client")
	var late: Dictionary = _report("late")
	for role: String in ["host", "client", "late"]:
		gut.p("%s report: %s" % [role, _read_text(_path(role, "json"))])
		var problems: PackedStringArray = _problems(role)
		for line: String in problems:
			gut.p("%s log: %s" % [role, line])
		assert_eq(problems.size(), 0, "no errors or warnings in the %s's log" % role)

	# The host played every floor and escaped.
	assert_true(host.get("ok", false), "the host finished the run: %s" % str(host.get("notes", [])))
	var floors: Array = host.get("floors", [])
	var total: int = floors.size()
	assert_gt(total, 0, "floors were played")
	var expected: Array[int] = []
	for number: int in range(1, total + 1):
		expected.append(number)
	assert_eq(_floor_numbers(floors), expected, "every floor in order")
	assert_eq(host.get("result", ""), "escaped", "the run ends as escaped")
	assert_eq(host.get("final_state", ""), "BREAK_ROOM", "everyone is back in the Break Room")
	for entry: Variant in floors:
		var floor_entry: Dictionary = entry
		var number: int = int(floor_entry["floor"])
		assert_true(floor_entry.get("departed", false), "the lift left floor %d" % number)
		# NEW (roadmap WP3, G5): a dead player can be reprinted on every floor, boss floors too.
		assert_gt(int(floor_entry.get("printers", 0)), 0, "floor %d has a 3D printer" % number)
		if floor_entry.get("boss_floor", false):
			assert_true((floor_entry.get("boss", {}) as Dictionary).get("defeated", false),
				"the boss on floor %d was beaten" % number)
		else:
			assert_true(floor_entry.get("lift_fixed", false), "the lift on floor %d was fixed" % number)
			assert_gt(int(floor_entry.get("enemies", 0)), 0, "floor %d has enemies" % number)
		if number > LATE_FLOOR:
			assert_eq((floor_entry["bodies"] as Array).size(), 3, "all 3 players have bodies on floor %d" % number)
	if total < DEATH_FLOOR:
		return
	assert_true((floors[total - 1] as Dictionary).get("boss_floor", false), "the last floor is a boss floor")

	# The late joiner waited as a spectator, then spawned on the next floor.
	var late_join: Dictionary = (floors[LATE_FLOOR - 1] as Dictionary).get("late_join", {})
	assert_true(late_join.get("joined", false), "the late joiner connected mid-floor")
	assert_true(late_join.get("waiting", false), "the late joiner waits for the next floor")
	assert_false(late_join.get("has_body", true), "the late joiner has no body until then")

	# A client died and was reprinted.
	var death: Dictionary = (floors[DEATH_FLOOR - 1] as Dictionary).get("death", {})
	assert_eq(int(death.get("player_id", 0)), int(client.get("player_id", -1)), "the client was the one who died")
	assert_true(death.get("died", false), "the client died")
	assert_true(death.get("ghost", false), "and became a ghost")
	assert_true(death.get("reprinted", false), "and was reprinted")

	# The client saw the same floors in the same departments, with a body on each.
	assert_true(client.get("ok", false), "the client finished: %s" % str(client.get("notes", [])))
	assert_eq(_floor_numbers(client.get("floors", [])), expected, "the client reached every floor")
	for index: int in mini((client.get("floors", []) as Array).size(), total):
		var seen: Dictionary = (client["floors"] as Array)[index]
		assert_eq(seen["department"], (floors[index] as Dictionary)["department"], "same department on floor %d" % (index + 1))
		assert_true(seen.get("has_body", false), "the client has a body on floor %d" % (index + 1))
	assert_eq(client.get("result", ""), "escaped", "the client saw the escape")
	assert_eq(client.get("final_state", ""), "BREAK_ROOM", "the client is back in the Break Room")
	# NEW 2026-11-13 (roadmap WP15): every PC has the same floor tasks in the same places, and hears they're done.
	var tasks_finished: int = 0
	var tasks_seen: int = 0
	for index: int in floors.size():
		var host_floor: Dictionary = floors[index]
		tasks_seen += (host_floor.get("tasks", []) as Array).size()
		if host_floor.has("task_finished"):
			tasks_finished += 1
		if index < (client.get("floors", []) as Array).size():
			assert_eq(((client["floors"] as Array)[index] as Dictionary).get("tasks", []), host_floor.get("tasks", []),
				"the client has the same tasks on floor %d" % (index + 1))
	assert_gt(tasks_seen, 0, "floor tasks turned up (the hamster wheel)")
	assert_eq(host.get("tasks_completed", -1) as int, tasks_finished, "the host heard about each finished task")
	assert_eq(client.get("tasks_completed", -1) as int, tasks_finished, "so did the client")
	for seen: Variant in late.get("floors", []):
		var late_floor: Dictionary = seen as Dictionary
		var host_floor: Dictionary = floors[(late_floor["floor"] as int) - 1]
		assert_eq(late_floor.get("tasks", []), host_floor.get("tasks", []),
			"the late joiner has the same tasks on floor %d" % (late_floor["floor"] as int))
	# NEW 2026-11-13 (roadmap WP15b): every PC is told who made each kill (the host beat every boss).
	var boss_floors: int = 0
	for entry: Variant in floors:
		if (entry as Dictionary).get("boss_floor", false):
			boss_floors += 1
	var host_id: String = str(host.get("my_player_id", ""))
	assert_eq(int((host.get("kills_credited", {}) as Dictionary).get(host_id, 0)), boss_floors, "the host counted its boss kills")
	assert_eq(int((client.get("kills_credited", {}) as Dictionary).get(host_id, 0)), boss_floors,
		"the client was told about every one of the host's kills")

	# The late joiner joined during a floor and played the rest.
	assert_true(late.get("ok", false), "the late joiner finished: %s" % str(late.get("notes", [])))
	assert_true(late.get("waiting_on_join", false), "it was told to wait for the next floor")
	assert_eq(_floor_numbers(late.get("floors", [])), expected.slice(LATE_FLOOR - 1),
		"it built the floor it joined on, then every later floor")
	for seen: Variant in late.get("floors", []):
		var number: int = int((seen as Dictionary)["floor"])
		assert_eq((seen as Dictionary).get("has_body", false), number > LATE_FLOOR,
			"the late joiner has a body on floor %d: %s" % [number, number > LATE_FLOOR])
	assert_eq(late.get("result", ""), "escaped", "the late joiner saw the escape")


## NEW 2026-11-11 (roadmap WP2): players leaving mid-floor. A client given a crowbar grabs a lift part and quits on
## floor 1: its crowbar drops, the part stays on the floor (let go) and the run goes on. On floor 2 the host walks
## out: the last client lands back in the main menu.
func test_players_leaving_mid_floor() -> void:
	var leave_port: String = "--port=%d" % (PORT + 1)
	_start("leave_host", "host", PackedStringArray(["--progress=%s" % _path("leave_host", "progress"),
		"--start_players=3", "--floors=3", "--boss_every=0", "--ride=%s" % QUICK_RIDE_SECONDS, "--leave_floor=1",
		"--leaver_id_file=%s" % _path("leaver", "id"), "--quit_floor=2", leave_port]))
	_start("stayer", "client", PackedStringArray([leave_port]))
	_start("leaver", "leaver", PackedStringArray(["--id_file=%s" % _path("leaver", "id"),
		"--host_progress=%s" % _path("leave_host", "progress"), leave_port]))
	var all_done: Callable = func() -> bool:
		return not _running("leave_host") and not _running("stayer") and not _running("leaver")
	await wait_until(all_done, QUICK_TIMEOUT)

	var host: Dictionary = _report("leave_host")
	var stayer: Dictionary = _report("stayer")
	var leaver: Dictionary = _report("leaver")
	for role: String in ["leave_host", "stayer", "leaver"]:
		gut.p("%s report: %s" % [role, _read_text(_path(role, "json"))])
		var problems: PackedStringArray = _problems(role)
		for line: String in problems:
			gut.p("%s log: %s" % [role, line])
		assert_eq(problems.size(), 0, "no errors or warnings in the %s's log" % role)

	assert_true(host.get("ok", false), "the host got to floor 2: %s" % str(host.get("notes", [])))
	assert_true(leaver.get("ok", false), "the leaver did its part: %s" % str(leaver.get("notes", [])))
	assert_true(leaver.get("held", false), "the leaver was holding the part when it quit")
	var floors: Array = host.get("floors", [])
	assert_eq(_floor_numbers(floors), [1, 2] as Array[int], "floor 1, then the host quits on floor 2")
	if floors.is_empty():
		return
	var leave: Dictionary = (floors[0] as Dictionary).get("leave", {})
	assert_true(leave.get("held_by_leaver", false), "the host saw the leaver holding the part")
	assert_true(leave.get("left", false), "the leaver left")
	assert_true(leave.get("body_gone", false), "its body is gone")
	assert_true(leave.get("crowbar_dropped", false), "its crowbar dropped for the team")
	assert_true(leave.get("part_still_there", false), "the lift part is still on the floor")
	assert_true(leave.get("part_let_go", false), "and nobody is holding it")
	assert_true((floors[0] as Dictionary).get("lift_fixed", false), "the lift could still be fixed")

	assert_true(stayer.get("host_left", false), "the client noticed the host leaving")
	assert_eq(stayer.get("state_after_host_left", ""), "MAIN_MENU", "and went back to the main menu")
	assert_eq(_floor_numbers(stayer.get("floors", [])), [1, 2] as Array[int], "after playing floors 1 and 2")
