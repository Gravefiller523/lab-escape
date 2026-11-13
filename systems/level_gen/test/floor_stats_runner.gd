extends Node
## NEW 2026-11-13 (floor generation step 6c): the floor tuning stats tool. Generates `count` floors for every
## department and every floor number of a run (1 to Config.game.run_floor_count), with the live
## config/floor_gen_tuning.tres, measures each (FloorStats), builds the first `builds` of each to time the
## build, then writes floor_stats.csv and floor_stats.md (the summary) and quits.
##
## Run it headless from a terminal (options after "--", all optional):
##   godot --headless --path . res://systems/level_gen/test/floor_stats_runner.tscn -- count=20 builds=2 players=1 out=C:/some/folder label=before
## The seeds are fixed (from the department, floor and sample number), so a run before and after a tuning
## change compares the same floors. Without `out` the files go to user://floorgen/stats/.

## The plan's intent (docs/design/floor-generation-plan.md, section 17), for the checks in the summary.
const PART_MIN_SHARE: float = 0.4
const EARLY_FLOORS: int = 3
const EARLY_KEYCARD_DOORS_MAX: int = 1
const EARLY_HAZARDS_MAX: int = 2
## A floor-to-floor change in average rooms outside this range is flagged (too slow or too fast growth).
const GROWTH_STEP_RANGE: Vector2 = Vector2(0.5, 3.0)

var _options: Dictionary[String, String] = {"count": "20", "builds": "2", "players": "1",
	"out": "user://floorgen/stats", "label": ""}


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.contains("="):
			_options[argument.get_slice("=", 0)] = argument.get_slice("=", 1)
	_run.call_deferred()


func _run() -> void:
	var count: int = maxi(_options["count"].to_int(), 1)
	var builds: int = maxi(_options["builds"].to_int(), 0)
	var players: int = maxi(_options["players"].to_int(), 1)
	var floors: int = Config.game.run_floor_count
	var tuning: FloorGenTuning = Config.floor_gen
	var rows: Array[Dictionary] = []
	var holder := Node3D.new()
	holder.name = "StatsFloor"
	add_child(holder)
	for department: DepartmentData in _departments():
		for floor_number: int in range(1, floors + 1):
			for sample: int in count:
				var floor_seed: int = absi(hash("stats|%s|%d|%d" % [department.id, floor_number, sample])) % 2147483646 + 1
				var started: int = Time.get_ticks_usec()
				var layout: FloorLayout = FloorGenerator.generate_from_seed(department, floor_number, floor_seed, tuning, players)
				var row: Dictionary = FloorStats.measure(layout, tuning)
				row["plan_ms"] = float(Time.get_ticks_usec() - started) / 1000.0
				if sample < builds:
					started = Time.get_ticks_usec()
					Level.build(layout, holder)
					row["build_ms"] = float(Time.get_ticks_usec() - started) / 1000.0
					Level.clear()
					await get_tree().process_frame
				rows.append(row)
			print("[floor_stats] %s floor %d: %d floors" % [department.id, floor_number, count])
	var folder: String = _options["out"]
	DirAccess.make_dir_recursive_absolute(folder)
	var suffix: String = ("_" + _options["label"]) if not _options["label"].is_empty() else ""
	_write(folder.path_join("floor_stats%s.csv" % suffix), FloorStats.to_csv(rows))
	_write(folder.path_join("floor_stats%s.md" % suffix), _summary(rows, count, players))
	print("[floor_stats] wrote %d floors to %s" % [rows.size(), ProjectSettings.globalize_path(folder)])
	get_tree().quit()


## Every department with its own floor tiles, by id.
func _departments() -> Array[DepartmentData]:
	var found: Array[DepartmentData] = []
	for resource: Resource in ContentRegistry.get_all(&"department"):
		var department := resource as DepartmentData
		if department != null and not FloorGenerator.tile_pool(department).is_empty():
			found.append(department)
	found.sort_custom(func(a: DepartmentData, b: DepartmentData) -> bool: return String(a.id) < String(b.id))
	return found


func _summary(rows: Array[Dictionary], count: int, players: int) -> String:
	var text := PackedStringArray()
	var label: String = _options["label"]
	text.append("# Floor stats%s" % ((" (" + label + ")") if not label.is_empty() else ""))
	text.append("")
	text.append("%d floors: %d per department per floor number, %d player(s), tuning config/floor_gen_tuning.tres. "
		% [rows.size(), count, players] + "Boss floors (every %d) are generated as normal floors here." % Config.game.boss_every_floors)
	text.append("Times are on this PC (plan = generate the layout, build = Level.build without the navigation bake).")
	text.append("")
	text.append("## Checks against the plan")
	text.append("")
	for line: String in _checks(rows):
		text.append("- " + line)
	text.append("")
	text.append("## By floor number (all departments)")
	text.append("")
	text.append(FloorStats.table(rows, "floor"))
	text.append("")
	text.append("## By department (all floors)")
	text.append("")
	text.append(FloorStats.table(rows, "department"))
	text.append("")
	return "\n".join(text) + "\n"


## Plain-language checks for the outliers the tuning looks for.
func _checks(rows: Array[Dictionary]) -> PackedStringArray:
	var lines := PackedStringArray()
	var fallbacks: int = FloorStats.count_where(rows, func(row: Dictionary) -> bool: return int(row["fallback"]) == 1)
	lines.append("Fallback floors: %d of %d. Average retries: %.2f." % [fallbacks, rows.size(), FloorStats.average(rows, "attempt")])
	# Growth: the average rooms per floor number, and the step from one floor to the next.
	var by_floor: Dictionary[int, Array] = {}
	for row: Dictionary in rows:
		var floor_number: int = row["floor"]
		if not by_floor.has(floor_number):
			by_floor[floor_number] = []
		by_floor[floor_number].append(row)
	var floor_numbers: Array[int] = []
	floor_numbers.assign(by_floor.keys())
	floor_numbers.sort()
	var rooms_line := PackedStringArray()
	var odd_steps := PackedStringArray()
	var previous: float = -1.0
	for floor_number: int in floor_numbers:
		var rooms: float = FloorStats.average(by_floor[floor_number], "rooms")
		rooms_line.append("%.1f" % rooms)
		if previous >= 0.0:
			var step: float = rooms - previous
			if step < GROWTH_STEP_RANGE.x or step > GROWTH_STEP_RANGE.y:
				odd_steps.append("%d to %d: %+.1f" % [floor_number - 1, floor_number, step])
		previous = rooms
	lines.append("Rooms per floor (floors 1 to %d): %s." % [floor_numbers.size(), ", ".join(rooms_line)])
	lines.append("Growth steps outside %+.1f to %+.1f rooms: %s." % [GROWTH_STEP_RANGE.x, GROWTH_STEP_RANGE.y,
		", ".join(odd_steps) if not odd_steps.is_empty() else "none"])
	var close: int = FloorStats.count_where(rows, func(row: Dictionary) -> bool:
		return int(row["parts"]) > 0 and float(row["part_path_min_share"]) < PART_MIN_SHARE)
	var with_parts: int = FloorStats.count_where(rows, func(row: Dictionary) -> bool: return int(row["parts"]) > 0)
	lines.append("Floors with a part closer than %d%% of the longest walk: %d of %d (the plan's minimum; the generator relaxes it when it must)."
		% [roundi(PART_MIN_SHARE * 100.0), close, with_parts])
	var early: Array[Dictionary] = []
	for row: Dictionary in rows:
		if int(row["floor"]) <= EARLY_FLOORS:
			early.append(row)
	var early_keycards: int = FloorStats.count_where(early, func(row: Dictionary) -> bool:
		return int(row["door_keycard"]) > EARLY_KEYCARD_DOORS_MAX)
	lines.append("Floors 1 to %d: %.1f locked doors on average (pry %.1f, power %.1f, debris %.1f, keycard %.1f); %d floors with more than %d keycard door."
		% [EARLY_FLOORS, FloorStats.average(early, "locks"), FloorStats.average(early, "door_pry"),
		FloorStats.average(early, "door_power"), FloorStats.average(early, "door_debris"),
		FloorStats.average(early, "door_keycard"), early_keycards, EARLY_KEYCARD_DOORS_MAX])
	var early_hazards: int = FloorStats.count_where(early, func(row: Dictionary) -> bool:
		return int(row["hazards"]) > EARLY_HAZARDS_MAX)
	lines.append("Floors 1 to %d: %.1f hazards on average; %d floors with more than %d."
		% [EARLY_FLOORS, FloorStats.average(early, "hazards"), early_hazards, EARLY_HAZARDS_MAX])
	var density := PackedStringArray()
	for floor_number: int in floor_numbers:
		density.append("%.2f" % FloorStats.average(by_floor[floor_number], "enemies_per_room"))
	lines.append("Enemy spawn spots per room (floors 1 to %d): %s." % [floor_numbers.size(), ", ".join(density)])
	return lines


func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("floor_stats: can't write %s" % path)
		return
	file.store_string(text)
	file.close()
