class_name TelemetryService
extends Node
## Autoload "Telemetry": a playtest log (NEW 2026-11-11, roadmap WP4). When it is on, every EventBus signal is written
## to a file on this PC, one JSON object per line, plus a summary line when a run ends (floors, time per floor,
## deaths, gems spent, upgrades). Nothing is sent anywhere. Off unless the game starts with `--telemetry` or the
## console says `telemetry on`. Signals are found with EventBus.get_signal_list(), so new ones need no change here.
## Spec: docs/systems/telemetry.md.

const LAUNCH_OPTION: String = "--telemetry"
const DEFAULT_FOLDER: String = "user://telemetry"

var _enabled: bool = false
var _folder: String = DEFAULT_FOLDER
var _file: FileAccess
var _path: String = ""
var _started_msec: int = 0
## Every connection made while on, so turning off removes exactly those.
var _connections: Array[Dictionary] = []
# The run summary, counted from the events.
var _run_started_msec: int = -1
var _floor_started_msec: int = -1
var _floor_seconds: Array[float] = []
var _floors: int = 0
var _deaths: int = 0
var _gems_spent: int = 0
var _upgrades: Array[String] = []


func _ready() -> void:
	DebugConsole.register_command(&"telemetry", _cmd_telemetry,
		"telemetry [on|off]: the playtest log (written to a file on this PC)", false)
	if OS.get_cmdline_args().has(LAUNCH_OPTION) or OS.get_cmdline_user_args().has(LAUNCH_OPTION):
		set_enabled(true)


func _exit_tree() -> void:
	set_enabled(false)


## For tests only: write logs into this folder instead of user://telemetry. Call while off.
func use_folder(folder: String) -> void:
	_folder = folder


func is_enabled() -> bool:
	return _enabled


func set_enabled(enabled: bool) -> void:
	if enabled == _enabled:
		return
	_enabled = enabled
	if enabled:
		_open_file()
		_connect_all()
	else:
		_disconnect_all()
		if _file != null:
			_file.close()
		_file = null


## A line of your own, e.g. log_custom(&"vendor_prices", {"stock": "stock_zoology_vending"}).
func log_custom(event_name: StringName, data: Dictionary) -> void:
	_write({"event": String(event_name), "data": _plain(data)})


## The file being written now, or "" when off.
func get_current_log_path() -> String:
	return _path if _enabled else ""


# --- Writing ----------------------------------------------------------------------------------------------------

func _open_file() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_folder))
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	_path = "%s/run_%s.jsonl" % [_folder, stamp]
	var number: int = 1
	while FileAccess.file_exists(_path):
		number += 1
		_path = "%s/run_%s_%d.jsonl" % [_folder, stamp, number]
	_file = FileAccess.open(_path, FileAccess.WRITE)
	_started_msec = Time.get_ticks_msec()
	if _file == null:
		push_warning("Telemetry: can't write %s" % _path)
		return
	_write({"event": "telemetry_started", "data": {"version": ProjectSettings.get_setting("application/config/version", ""),
		"build": BuildInfo.get_build_id(),
		"player_id": Net.local_player_id(), "host": Net.is_host()}})


func _write(entry: Dictionary) -> void:
	if not _enabled or _file == null:
		return
	entry["t"] = snappedf(float(Time.get_ticks_msec() - _started_msec) / 1000.0, 0.01)
	_file.store_line(JSON.stringify(entry))
	_file.flush()


## Values JSON can hold: nodes become their name (and, for players, their id), vectors become lists.
static func _plain(value: Variant) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_STRING_NAME:
			return str(value)
		TYPE_VECTOR2:
			var v2: Vector2 = value
			return [snappedf(v2.x, 0.01), snappedf(v2.y, 0.01)]
		TYPE_VECTOR3:
			var v3: Vector3 = value
			return [snappedf(v3.x, 0.01), snappedf(v3.y, 0.01), snappedf(v3.z, 0.01)]
		TYPE_OBJECT:
			var node := value as Node
			if node == null or not is_instance_valid(node):
				return null
			var body := node as PlayerCharacter
			return {"node": String(node.name), "player_id": body.player_id} if body != null else String(node.name)
		TYPE_ARRAY:
			var items: Array = []
			for item: Variant in value as Array:
				items.append(_plain(item))
			return items
		TYPE_DICTIONARY:
			var out: Dictionary = {}
			var source: Dictionary = value
			for key: Variant in source:
				out[str(key)] = _plain(source[key])
			return out
	return str(value)


# --- Listening to every EventBus signal ---------------------------------------------------------------------------

func _connect_all() -> void:
	for info: Dictionary in EventBus.get_signal_list():
		var signal_name: StringName = info["name"]
		var count: int = (info["args"] as Array).size()
		var handler: Callable = _handler_for(signal_name, count)
		if handler.is_valid() and not EventBus.is_connected(signal_name, handler):
			EventBus.connect(signal_name, handler)
			_connections.append({"signal": signal_name, "handler": handler})
	EventBus.run_started.connect(_on_run_started)
	EventBus.floor_ready.connect(_on_floor_ready)
	EventBus.player_died.connect(_on_player_died)
	EventBus.vendor_purchase.connect(_on_vendor_purchase)
	EventBus.upgrade_gained.connect(_on_upgrade_gained)
	EventBus.run_ended.connect(_on_run_ended)


func _disconnect_all() -> void:
	for connection: Dictionary in _connections:
		var signal_name: StringName = connection["signal"]
		var handler: Callable = connection["handler"]
		if EventBus.is_connected(signal_name, handler):
			EventBus.disconnect(signal_name, handler)
	_connections.clear()
	EventBus.run_started.disconnect(_on_run_started)
	EventBus.floor_ready.disconnect(_on_floor_ready)
	EventBus.player_died.disconnect(_on_player_died)
	EventBus.vendor_purchase.disconnect(_on_vendor_purchase)
	EventBus.upgrade_gained.disconnect(_on_upgrade_gained)
	EventBus.run_ended.disconnect(_on_run_ended)


## GDScript has no "any number of arguments" functions, so there is one small handler per argument count.
func _handler_for(signal_name: StringName, count: int) -> Callable:
	match count:
		0:
			return func() -> void: _log_event(signal_name, [])
		1:
			return func(a: Variant) -> void: _log_event(signal_name, [a])
		2:
			return func(a: Variant, b: Variant) -> void: _log_event(signal_name, [a, b])
		3:
			return func(a: Variant, b: Variant, c: Variant) -> void: _log_event(signal_name, [a, b, c])
		4:
			return func(a: Variant, b: Variant, c: Variant, d: Variant) -> void: _log_event(signal_name, [a, b, c, d])
		5:
			return func(a: Variant, b: Variant, c: Variant, d: Variant, e: Variant) -> void:
				_log_event(signal_name, [a, b, c, d, e])
	push_warning("Telemetry: EventBus.%s has %d arguments; not logged (add a handler for that many)." % [signal_name, count])
	return Callable()


func _log_event(signal_name: StringName, args: Array) -> void:
	_write({"event": String(signal_name), "args": _plain(args)})


# --- The run summary --------------------------------------------------------------------------------------------

func _on_run_started(_run_seed: int) -> void:
	_run_started_msec = Time.get_ticks_msec()
	_floor_started_msec = -1
	_floor_seconds.clear()
	_floors = 0
	_deaths = 0
	_gems_spent = 0
	_upgrades.clear()


func _on_floor_ready(floor_number: int, _department_id: StringName) -> void:
	_close_floor()
	_floor_started_msec = Time.get_ticks_msec()
	_floors = maxi(_floors, floor_number)


func _on_player_died(_player_id: int, _at: Vector3) -> void:
	_deaths += 1


func _on_vendor_purchase(_player_id: int, _item_id: StringName, price: int) -> void:
	_gems_spent += price


func _on_upgrade_gained(_player_id: int, upgrade_id: StringName) -> void:
	_upgrades.append(String(upgrade_id))


func _on_run_ended(result: StringName) -> void:
	_close_floor()
	var minutes: float = float(Time.get_ticks_msec() - _run_started_msec) / 60000.0 if _run_started_msec >= 0 else 0.0
	_write({"event": "run_summary", "data": {"result": String(result), "floors_reached": _floors,
		"minutes": snappedf(minutes, 0.1), "seconds_per_floor": _floor_seconds.duplicate(), "deaths": _deaths,
		"gems_spent": _gems_spent, "upgrades_found": _upgrades.duplicate(), "players": Net.get_player_count()}})


func _close_floor() -> void:
	if _floor_started_msec >= 0:
		_floor_seconds.append(snappedf(float(Time.get_ticks_msec() - _floor_started_msec) / 1000.0, 0.1))
	_floor_started_msec = -1


# --- Console ----------------------------------------------------------------------------------------------------

func _cmd_telemetry(args: PackedStringArray, _player_id: int) -> String:
	if not args.is_empty():
		set_enabled(args[0] == "on")
	return "Telemetry is %s.%s" % ["on" if _enabled else "off",
		" Writing to %s" % ProjectSettings.globalize_path(_path) if _enabled else ""]
