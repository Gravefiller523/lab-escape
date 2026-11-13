extends GutTest
## Achievements (NEW 2026-11-13, roadmap WP18; docs/systems/achievements.md). Counting is switched on for the tests,
## and the profile lives in a test folder, so the real player's progress is never touched.

const FOLDER: String = "user://test_achievements"


func before_each() -> void:
	SaveSystem.use_folder(FOLDER)
	for path: String in DirAccess.get_files_at(FOLDER):
		DirAccess.remove_absolute(FOLDER.path_join(path))
	SaveSystem.use_folder(FOLDER)
	SaveSystem.count_everywhere(true)
	Achievements.count_everywhere(true)


func after_each() -> void:
	Achievements.count_everywhere(false)
	SaveSystem.count_everywhere(false)
	SaveSystem.use_folder(SaveService.DEFAULT_FOLDER)


func _unlocks(id: StringName) -> int:
	var data := ContentRegistry.get_content(id) as AchievementData
	return Achievements.get_unlock_log().count(data.steam_api_name)


func test_about_fifteen_achievements_all_with_known_events() -> void:
	var all: Array[StringName] = ContentRegistry.get_all_ids(&"achievement")
	assert_between(all.size(), 12, 20, "about 15 achievements")
	assert_eq(AchievementsService.unknown_trigger_events(), PackedStringArray(), "every trigger_event is an EventBus signal")
	var api_names: Dictionary[String, bool] = {}
	for id: StringName in all:
		var data := ContentRegistry.get_content(id) as AchievementData
		assert_false(data.display_name.is_empty(), "%s has a name" % id)
		assert_false(data.description.is_empty(), "%s says how to get it" % id)
		assert_false(api_names.has(data.steam_api_name), "%s's Steam name is its own" % id)
		api_names[data.steam_api_name] = true


func test_counts_matching_events_and_unlocks_once() -> void:
	watch_signals(EventBus)
	EventBus.run_ended.emit(&"wiped")
	assert_eq(Achievements.get_progress(&"achievement_first_escape"), 0, "a wipe isn't an escape")
	EventBus.run_ended.emit(&"escaped")
	assert_true(Achievements.is_unlocked(&"achievement_first_escape"), "escaped once: unlocked")
	assert_signal_emitted_with_parameters(EventBus, "achievement_unlocked", [&"achievement_first_escape"])
	assert_eq(Achievements.get_progress(&"achievement_escape_5"), 1, "and one towards Overtime Champion")
	EventBus.run_ended.emit(&"escaped")
	assert_eq(_unlocks(&"achievement_first_escape"), 1, "unlocked only once")


func test_unlocks_at_the_required_count() -> void:
	for index: int in 4:
		EventBus.run_ended.emit(&"escaped")
	assert_false(Achievements.is_unlocked(&"achievement_escape_5"), "4 of 5")
	EventBus.run_ended.emit(&"escaped")
	assert_true(Achievements.is_unlocked(&"achievement_escape_5"), "5 of 5")


func test_match_id_filters() -> void:
	EventBus.boss_defeated.emit(&"boss_giant_rat")
	assert_true(Achievements.is_unlocked(&"achievement_beat_giant_rat"))
	assert_false(Achievements.is_unlocked(&"achievement_beat_robobrain"), "a different boss")


func test_ignores_other_players_when_local_only() -> void:
	var me: int = Net.local_player_id()
	EventBus.player_died.emit(me + 1, Vector3.ZERO)
	assert_false(Achievements.is_unlocked(&"achievement_first_death"), "someone else died")
	EventBus.player_died.emit(me, Vector3.ZERO)
	assert_true(Achievements.is_unlocked(&"achievement_first_death"), "you died")
	EventBus.kill_credited.emit(&"enemy_rat", me + 1)
	EventBus.kill_credited.emit(&"enemy_rat", me)
	assert_eq(Achievements.get_progress(&"achievement_kills_100"), 1, "only your kills (the killer is the first number)")


func test_progress_is_kept_in_the_profile() -> void:
	EventBus.kill_credited.emit(&"enemy_rat", Net.local_player_id())
	EventBus.kill_credited.emit(&"enemy_bat", Net.local_player_id())
	SaveSystem.save_profile()
	SaveSystem.use_folder(FOLDER)
	assert_eq(Achievements.get_progress(&"achievement_kills_100"), 2, "still there after loading the profile again")


func test_nothing_counts_outside_the_game_world() -> void:
	Achievements.count_everywhere(false)
	SaveSystem.count_everywhere(false)
	EventBus.run_ended.emit(&"escaped")
	assert_eq(Achievements.get_progress(&"achievement_first_escape"), 0)


func test_steam_hears_about_unlocks_and_stats() -> void:
	var fake := FakeSteamApi.new()
	fake.steam_available = true
	var session := SteamSessionService.new()
	session.use_backend(fake, GameConfig.new())
	add_child_autofree(session)
	await wait_process_frames(1)
	session.set_stat("STAT_KILLS", 7)
	session.unlock_achievement("ACH_FIRST_ESCAPE")
	assert_eq(fake.stats_set.get("STAT_KILLS", -1), 7)
	assert_eq(fake.achievements_set, ["ACH_FIRST_ESCAPE"] as Array[String])
	assert_gt(fake.stores, 0, "sent to Steam")
	var offline := FakeSteamApi.new()
	var without := SteamSessionService.new()
	without.use_backend(offline, GameConfig.new())
	add_child_autofree(without)
	await wait_process_frames(1)
	without.unlock_achievement("ACH_FIRST_ESCAPE")
	assert_eq(offline.achievements_set.size(), 0, "no Steam: nothing is sent")


func test_a_new_achievement_file_needs_no_code() -> void:
	var data := AchievementData.new()
	data.id = &"achievement_test_new"
	data.display_name = "Test"
	data.steam_api_name = "ACH_TEST_NEW"
	data.trigger_event = &"lift_ready"
	data.required_count = 2
	ContentRegistry.register_content(data)
	Achievements.call("_connect_all")
	EventBus.lift_ready.emit()
	EventBus.lift_ready.emit()
	assert_true(Achievements.is_unlocked(&"achievement_test_new"), "a data file and an existing signal are enough")
	Achievements.call("_connect_all")
