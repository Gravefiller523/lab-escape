class_name SaveService
extends Node
## Autoload "SaveSystem" (NEW 2026-11-12, roadmap WP12): the player's profile on their own PC (cosmetics, outfit,
## lifetime stats, hints seen), saved as user://profile_<steam id>.json ("local" without Steam). Versioned: an older
## file is upgraded step by step when it loads; a broken file is renamed .broken and a fresh profile starts.
## Stats count what this PC sees on EventBus. Saved when a run ends and when the game closes. Nothing is sent
## anywhere (Steam Cloud backs the file up once it is set up on the Steamworks site). Spec: docs/systems/save_load.md.

signal profile_loaded()

## Version 1: cosmetics, loadout, stats, seen_hint_ids. A new version adds a _migrate_<n>_to_<n+1> step below.
const SAVE_VERSION: int = 1
const DEFAULT_FOLDER: String = "user://"

var _folder: String = DEFAULT_FOLDER
var _profile: PlayerProfile
var _path: String = ""
var _count_everywhere: bool = false


func _ready() -> void:
	EventBus.run_started.connect(func(_run_seed: int) -> void: increment_stat(&"runs_started"))
	EventBus.run_ended.connect(_on_run_ended)
	EventBus.floor_ready.connect(func(floor_number: int, _department_id: StringName) -> void:
		if not _counting():
			return
		var profile: PlayerProfile = get_profile()
		profile.stats["floors_reached_best"] = maxi((profile.stats.get("floors_reached_best", 0) as int), floor_number))
	# CHANGED 2026-11-13 (roadmap WP15b): kill_credited reaches every PC, so clients' kills count too.
	EventBus.kill_credited.connect(func(_enemy_id: StringName, killer_player_id: int) -> void:
		if killer_player_id != 0 and killer_player_id == Net.local_player_id():
			increment_stat(&"enemies_killed"))
	EventBus.player_died.connect(func(player_id: int, _at: Vector3) -> void:
		if player_id == Net.local_player_id():
			increment_stat(&"deaths"))
	EventBus.player_reprinted.connect(func(player_id: int) -> void:
		if player_id == Net.local_player_id():
			increment_stat(&"reprints"))
	EventBus.boss_defeated.connect(func(boss_id: StringName) -> void:
		increment_stat(StringName("boss_defeated:%s" % boss_id)))
	EventBus.upgrade_gained.connect(_on_upgrade_gained)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _profile != null:
		save_profile()


## For tests only: keep profiles in this folder instead of user://, and forget the loaded one.
func use_folder(folder: String) -> void:
	_folder = folder
	_profile = null


## For tests only: count stats outside the game world too (they only count in game_flow's world, so unit tests and
## systems' test scenes never change the real profile).
func count_everywhere(on: bool) -> void:
	_count_everywhere = on


func _counting() -> bool:
	return _count_everywhere or GameWorld.current() != null


## The profile, loaded from disk the first time it's asked for.
func get_profile() -> PlayerProfile:
	if _profile == null:
		_load()
	return _profile


## Writes the profile now (also done when a run ends and when the game closes).
func save_profile() -> void:
	var profile: PlayerProfile = get_profile()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_folder))
	var file: FileAccess = FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveSystem: can't write %s" % _path)
		return
	file.store_string(JSON.stringify(profile.to_dict(), "  "))


func get_stat(stat: StringName) -> int:
	return get_profile().stats.get(String(stat), 0) as int


func increment_stat(stat: StringName, amount: int = 1) -> void:
	if not _counting():
		return
	var profile: PlayerProfile = get_profile()
	profile.stats[String(stat)] = (profile.stats.get(String(stat), 0) as int) + amount


## NEW (roadmap WP12, for ui's Hints): first-time hints already shown to this player.
func has_seen_hint(hint_id: StringName) -> bool:
	return get_profile().seen_hint_ids.has(hint_id)


func reset_seen_hints() -> void:
	get_profile().seen_hint_ids.clear()
	save_profile()


func mark_hint_seen(hint_id: StringName) -> void:
	var profile: PlayerProfile = get_profile()
	if not profile.seen_hint_ids.has(hint_id):
		profile.seen_hint_ids.append(hint_id)
		save_profile()


## The file this PC's profile lives in.
func get_profile_path() -> String:
	get_profile()
	return _path


## Upgrades a saved dictionary from any older version to SAVE_VERSION, one step at a time.
static func migrate(data: Dictionary) -> Dictionary:
	var upgraded: Dictionary = data.duplicate(true)
	var version: int = (upgraded.get("save_version", 0) as int)
	if version < 1:
		upgraded = _migrate_0_to_1(upgraded)
	upgraded["save_version"] = SAVE_VERSION
	return upgraded


## Version 0 (the spec's sketch before WP12): no seen_hint_ids, and stats could be missing.
static func _migrate_0_to_1(data: Dictionary) -> Dictionary:
	if not data.has("stats"):
		data["stats"] = {}
	if not data.has("seen_hint_ids"):
		data["seen_hint_ids"] = []
	data["save_version"] = 1
	return data


func _load() -> void:
	var owner_id: String = str(SteamSession.get_local_steam_id()) if SteamSession.is_steam_running() else "local"
	_path = _folder.path_join("profile_%s.json" % owner_id)
	_profile = PlayerProfile.new()
	if FileAccess.file_exists(_path):
		var json := JSON.new()
		var ok: bool = json.parse(FileAccess.get_file_as_string(_path)) == OK and json.data is Dictionary
		if ok:
			_profile = PlayerProfile.from_dict(migrate(json.data as Dictionary))
		else:
			push_warning("SaveSystem: %s is broken; it was renamed .broken and a new profile started." % _path)
			DirAccess.rename_absolute(ProjectSettings.globalize_path(_path),
				ProjectSettings.globalize_path(_path + ".broken"))
	profile_loaded.emit()


func _on_run_ended(result: StringName) -> void:
	if not _counting():
		return
	if result == &"escaped":
		increment_stat(&"runs_escaped")
	save_profile()


func _on_upgrade_gained(player_id: int, upgrade_id: StringName) -> void:
	if player_id != Net.local_player_id():
		return
	var upgrade: ContentData = ContentRegistry.get_content(upgrade_id)
	increment_stat(&"cybernetics_installed" if upgrade is CyberneticData else &"mutations_gained")
