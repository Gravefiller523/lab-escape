extends GutTest
## Tests for save_load (docs/systems/save_load.md, built in roadmap WP12): the player's profile on their own PC.
## Each test uses its own folder under user://test_save_load/, never the real profile.

const FOLDER: String = "user://test_save_load"
const FIXTURE_V0: String = "res://tests/unit/save_load/fixtures/profile_v0.json"


func before_each() -> void:
	var absolute: String = ProjectSettings.globalize_path(FOLDER)
	DirAccess.make_dir_recursive_absolute(absolute)
	for file: String in DirAccess.get_files_at(absolute):
		DirAccess.remove_absolute(absolute.path_join(file))
	SaveSystem.use_folder(FOLDER)
	SaveSystem.count_everywhere(true)


func after_each() -> void:
	SaveSystem.count_everywhere(false)
	SaveSystem.use_folder(SaveService.DEFAULT_FOLDER)


func _write(text: String) -> void:
	var path: String = SaveSystem.get_profile_path()
	SaveSystem.use_folder(FOLDER)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_new_profile_defaults() -> void:
	var profile: PlayerProfile = SaveSystem.get_profile()
	assert_eq(profile.unlocked_cosmetic_ids.size(), 0)
	assert_eq(profile.loadout.size(), 0)
	assert_eq(SaveSystem.get_stat(&"runs_started"), 0, "every stat starts at 0")


func test_round_trip() -> void:
	SaveSystem.increment_stat(&"runs_escaped", 2)
	SaveSystem.get_profile().unlocked_cosmetic_ids.append(&"cosmetic_lab_coat")
	SaveSystem.mark_hint_seen(&"hint_gems")
	SaveSystem.save_profile()
	SaveSystem.use_folder(FOLDER)
	assert_eq(SaveSystem.get_stat(&"runs_escaped"), 2, "stats survive a restart")
	assert_has(SaveSystem.get_profile().unlocked_cosmetic_ids, &"cosmetic_lab_coat")
	assert_true(SaveSystem.has_seen_hint(&"hint_gems"), "so do the hints you've seen")


func test_migration_from_version_0_fixture() -> void:
	_write(FileAccess.get_file_as_string(FIXTURE_V0))
	var profile: PlayerProfile = SaveSystem.get_profile()
	assert_has(profile.unlocked_cosmetic_ids, &"cosmetic_lab_coat", "old cosmetics carried over")
	assert_eq(profile.loadout.get("body"), "cosmetic_lab_coat", "and the outfit")
	assert_eq(profile.seen_hint_ids.size(), 0, "new fields get their defaults")
	assert_eq(int(SaveService.migrate({}).get("save_version")), SaveService.SAVE_VERSION)


func test_broken_file_is_renamed_not_crash() -> void:
	_write("{ this is not json")
	var path: String = SaveSystem.get_profile_path()
	SaveSystem.use_folder(FOLDER)
	var profile: PlayerProfile = SaveSystem.get_profile()
	assert_not_null(profile, "a fresh profile instead of a crash")
	assert_true(FileAccess.file_exists(path + ".broken"), "the broken file is kept, renamed")
	assert_engine_error_count(0)


func test_unknown_ids_are_kept() -> void:
	_write(FileAccess.get_file_as_string(FIXTURE_V0))
	assert_has(SaveSystem.get_profile().unlocked_cosmetic_ids, &"cosmetic_removed_long_ago",
		"content that no longer exists stays in the file")
	SaveSystem.save_profile()
	SaveSystem.use_folder(FOLDER)
	assert_has(SaveSystem.get_profile().unlocked_cosmetic_ids, &"cosmetic_removed_long_ago", "even after saving")


func test_increment_stat() -> void:
	SaveSystem.increment_stat(&"enemies_killed")
	SaveSystem.increment_stat(&"enemies_killed", 4)
	assert_eq(SaveSystem.get_stat(&"enemies_killed"), 5)


func test_events_count_stats_for_you_only() -> void:
	var me: int = Net.local_player_id()
	EventBus.player_died.emit(me, Vector3.ZERO)
	EventBus.player_died.emit(me + 1, Vector3.ZERO)
	EventBus.boss_defeated.emit(&"boss_giant_rat")
	assert_eq(SaveSystem.get_stat(&"deaths"), 1, "only your own deaths")
	# NEW 2026-11-13 (roadmap WP15b): kills come from the kill credit every PC gets, so a client's kills count too.
	EventBus.kill_credited.emit(&"enemy_rat", me)
	EventBus.kill_credited.emit(&"enemy_rat", me + 1)
	EventBus.kill_credited.emit(&"enemy_rat", 0)
	assert_eq(SaveSystem.get_stat(&"enemies_killed"), 1, "only your own kills")
	assert_eq(SaveSystem.get_stat(&"boss_defeated:boss_giant_rat"), 1)


func test_nothing_counts_outside_the_game_world() -> void:
	SaveSystem.count_everywhere(false)
	EventBus.player_died.emit(Net.local_player_id(), Vector3.ZERO)
	assert_eq(SaveSystem.get_stat(&"deaths"), 0, "tests and test scenes never change the real profile")
