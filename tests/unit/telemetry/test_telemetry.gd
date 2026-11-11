extends GutTest
## Tests for telemetry (docs/systems/telemetry.md): its own TelemetryService writing into a test folder.

const FOLDER: String = "user://test_telemetry"

var _telemetry: TelemetryService


func before_each() -> void:
	var absolute: String = ProjectSettings.globalize_path(FOLDER)
	DirAccess.make_dir_recursive_absolute(absolute)
	for file: String in DirAccess.get_files_at(absolute):
		DirAccess.remove_absolute(absolute.path_join(file))
	_telemetry = TelemetryService.new()
	_telemetry.use_folder(FOLDER)
	add_child_autofree(_telemetry)


func after_each() -> void:
	_telemetry.set_enabled(false)


func _lines() -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	var absolute: String = ProjectSettings.globalize_path(FOLDER)
	for file: String in DirAccess.get_files_at(absolute):
		for text: String in FileAccess.get_file_as_string(absolute.path_join(file)).split("\n", false):
			var parsed: Variant = JSON.parse_string(text)
			assert_true(parsed is Dictionary, "a JSON object: %s" % text)
			if parsed is Dictionary:
				lines.append(parsed as Dictionary)
	return lines


func _events(event_name: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for line: Dictionary in _lines():
		if line.get("event", "") == event_name:
			found.append(line)
	return found


func test_disabled_writes_nothing() -> void:
	assert_false(_telemetry.is_enabled(), "off by default")
	EventBus.achievement_unlocked.emit(&"achievement_test")
	_telemetry.log_custom(&"custom", {"a": 1})
	assert_eq(_lines().size(), 0, "no file, no lines")
	assert_eq(_telemetry.get_current_log_path(), "")


func test_every_signal_connected() -> void:
	_telemetry.set_enabled(true)
	for info: Dictionary in EventBus.get_signal_list():
		assert_gt(EventBus.get_signal_connection_list(info["name"]).size(), 0, "%s is listened to" % info["name"])
	EventBus.lift_ready.emit()
	EventBus.achievement_unlocked.emit(&"achievement_test")
	EventBus.enemy_killed.emit(&"enemy_rat", Vector3(1, 0, 2), 765)
	assert_eq(_events("lift_ready").size(), 1, "no arguments")
	assert_eq(_events("achievement_unlocked").size(), 1, "one argument")
	assert_eq(_events("enemy_killed").size(), 1, "three arguments")
	_telemetry.set_enabled(false)
	EventBus.lift_ready.emit()
	assert_eq(_events("lift_ready").size(), 1, "turned off: nothing more is written")


func test_line_is_valid_json() -> void:
	_telemetry.set_enabled(true)
	assert_string_contains(_telemetry.get_current_log_path(), FOLDER)
	EventBus.enemy_killed.emit(&"enemy_rat", Vector3(1, 0, 2), 765)
	_telemetry.log_custom(&"price_check", {"stock": &"stock_zoology_vending", "price": 3})
	var killed: Dictionary = _events("enemy_killed")[0]
	assert_true(killed.has("t"), "a timestamp")
	assert_eq(killed["args"], ["enemy_rat", [1.0, 0.0, 2.0], 765.0], "ids as text, vectors as lists")
	var custom: Dictionary = _events("price_check")[0]
	assert_eq((custom["data"] as Dictionary)["stock"], "stock_zoology_vending")


func test_nodes_written_as_names() -> void:
	_telemetry.set_enabled(true)
	var crate := Node3D.new()
	crate.name = "Crate7"
	add_child_autofree(crate)
	EventBus.key_object_respawned.emit(crate)
	var line: Dictionary = _events("key_object_respawned")[0]
	assert_eq(line["args"], ["Crate7"], "a node is written as its name")


func test_run_summary_is_written_when_a_run_ends() -> void:
	_telemetry.set_enabled(true)
	EventBus.run_started.emit(7)
	EventBus.player_died.emit(1, Vector3.ZERO)
	EventBus.vendor_purchase.emit(1, &"item_crowbar", 3)
	EventBus.upgrade_gained.emit(1, &"mutation_fly")
	EventBus.run_ended.emit(&"wiped")
	var summaries: Array[Dictionary] = _events("run_summary")
	assert_eq(summaries.size(), 1, "one summary")
	var data: Dictionary = summaries[0]["data"]
	assert_eq(data["result"], "wiped")
	assert_eq(int(data["deaths"]), 1)
	assert_eq(int(data["gems_spent"]), 3)
	assert_eq(data["upgrades_found"], ["mutation_fly"])
