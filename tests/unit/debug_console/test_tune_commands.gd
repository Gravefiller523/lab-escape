extends GutTest
## Tests for the feel-tuning console commands (TuneCommands, NEW 2026-10-29). Each test works on its own
## FeelTuning copy, never the live Config.feel, so nothing leaks into other tests or the project files.


func _feel() -> FeelTuning:
	var feel := FeelTuning.new()
	feel.player = PlayerTuning.new()
	feel.props = PropTuning.new()
	feel.ai = AiTuning.new()
	return feel


func test_live_feel_tuning_is_loaded_with_every_section() -> void:
	assert_not_null(Config.feel, "Config.feel exists")
	assert_not_null(Config.feel.player, "player section")
	assert_not_null(Config.feel.props, "props section")
	assert_not_null(Config.feel.ai, "ai section")


func test_player_scene_and_config_share_one_player_tuning() -> void:
	var from_scene: PlayerTuning = preload("res://systems/player/player_tuning.tres")
	assert_same(Config.feel.player, from_scene, "tuning the player in feel_tuning.tres changes the real player")


func test_tune_changes_a_number() -> void:
	var feel := _feel()
	var output: String = TuneCommands.tune(PackedStringArray(["props.throw_force", "25.4"]), feel)
	assert_almost_eq(feel.props.throw_force, 25.4, 0.001)
	assert_string_contains(output, "25.4")


func test_tune_shows_one_number() -> void:
	var feel := _feel()
	feel.ai.turn_speed = 6.0
	assert_string_contains(TuneCommands.tune(PackedStringArray(["ai.turn_speed"]), feel), "6")


func test_tune_lists_a_section() -> void:
	var output: String = TuneCommands.tune(PackedStringArray(["player"]), _feel())
	assert_string_contains(output, "player.walk_speed")
	assert_string_contains(output, "player.gravity")


func test_tune_refuses_bad_names_and_values() -> void:
	var feel := _feel()
	assert_string_contains(TuneCommands.tune(PackedStringArray(["nope.walk_speed", "3"]), feel), "No section")
	assert_string_contains(TuneCommands.tune(PackedStringArray(["player.nope", "3"]), feel), "No number")
	assert_string_contains(TuneCommands.tune(PackedStringArray(["player.walk_speed", "fast"]), feel), "isn't a valid")
	assert_almost_eq(feel.player.walk_speed, PlayerTuning.new().walk_speed, 0.001, "unchanged after bad input")


func test_tune_save_only_in_the_editor() -> void:
	assert_string_contains(TuneCommands.save(_feel(), false), "only works")
