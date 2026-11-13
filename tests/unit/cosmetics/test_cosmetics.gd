extends GutTest
## Cosmetics and the jacket closet (NEW 2026-11-13, roadmap WP17; docs/systems/cosmetics.md). Solo: this PC is the
## host and the player. The profile lives in a test folder, so the real player's unlocks and outfit are never touched.

const FOLDER: String = "user://test_cosmetics"
const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")
const WAIT: float = 3.0
## Decision D6 (2026-11-11): 6 starter items, 3 for runs escaped (1, 3, 10), 1 per boss beaten, 2 from achievements.
const STARTERS: int = 6
const RUN_COUNTS: Array[int] = [1, 3, 10]
const FROM_ACHIEVEMENTS: int = 2

var _me: int = 0
var _world: Node3D


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	for path: String in DirAccess.get_files_at(FOLDER):
		DirAccess.remove_absolute(FOLDER.path_join(path))
	SaveSystem.use_folder(FOLDER)
	SaveSystem.count_everywhere(true)
	Achievements.count_everywhere(true)
	_me = Net.local_player_id()
	_world = null


func after_each() -> void:
	if UI.get_open_screen() == CosmeticsService.SCREEN_CLOSET:
		UI.close_screen()
	if Net.get_record(_me) != null:
		Net.update_record(_me, &"cosmetic_loadout", {})
	for upgrade_id: StringName in Upgrades.get_upgrades(_me):
		Upgrades.remove(_me, upgrade_id)
	Achievements.count_everywhere(false)
	SaveSystem.count_everywhere(false)
	SaveSystem.use_folder(SaveService.DEFAULT_FOLDER)
	await wait_process_frames(2)


## A body for this PC's player, dressed the way the game does it (player_spawned).
func _spawn_me() -> PlayerCharacter:
	_world = Node3D.new()
	add_child_autofree(_world)
	var body := PLAYER_SCENE.instantiate() as PlayerCharacter
	body.player_id = _me
	body.name = str(_me)
	_world.add_child(body)
	body.set_input_override(PlayerInputState.new())
	EventBus.player_spawned.emit(_me, body)
	return body


func _dresser(body: PlayerCharacter) -> CosmeticDresser:
	return body.get_node_or_null(NodePath(CosmeticDresser.NODE_NAME)) as CosmeticDresser


func _all() -> Array[CosmeticData]:
	var found: Array[CosmeticData] = []
	for content: ContentData in ContentRegistry.get_all(&"cosmetic"):
		found.append(content as CosmeticData)
	return found


func _closet() -> ClosetScreen:
	return UI.get_child(UI.get_child_count() - 2) as ClosetScreen


func test_starter_set_and_unlocks_follow_decision_d6() -> void:
	var starters: int = 0
	var run_counts: Array[int] = []
	var bosses: Array[StringName] = []
	var achievements: int = 0
	for data: CosmeticData in _all():
		assert_has(CosmeticsService.SLOTS, data.slot, "%s is in a known slot" % data.id)
		assert_not_null(data.scene, "%s has a model" % data.id)
		assert_false(data.description.is_empty(), "%s says how to get it" % data.id)
		if data.unlock == null:
			starters += 1
			continue
		match data.unlock.kind:
			&"runs_completed":
				run_counts.append(data.unlock.count)
			&"boss_defeated":
				bosses.append(data.unlock.boss_id)
			&"achievement":
				achievements += 1
				assert_not_null(ContentRegistry.get_content(data.unlock.achievement_id), "%s's achievement exists" % data.id)
			_:
				fail_test("%s has an unknown unlock rule '%s'" % [data.id, data.unlock.kind])
	run_counts.sort()
	assert_eq(starters, STARTERS, "starter items")
	assert_eq(run_counts, RUN_COUNTS, "escape 1, 3 and 10 times")
	assert_eq(achievements, FROM_ACHIEVEMENTS, "from achievements")
	for boss_id: StringName in ContentRegistry.get_all_ids(&"boss"):
		assert_eq(bosses.count(boss_id), 1, "one cosmetic for beating %s" % boss_id)


func test_default_cosmetics_unlocked() -> void:
	assert_true(Cosmetics.is_unlocked(&"cosmetic_hat_hard_hat"), "a starter is yours from day one")
	assert_false(Cosmetics.is_unlocked(&"cosmetic_hat_rat_ears"), "a boss cosmetic starts locked")
	assert_false(Cosmetics.is_unlocked(&"cosmetic_nothing"), "an unknown id isn't")
	assert_eq(Cosmetics.get_unlocked().size(), STARTERS, "only the starters in a fresh profile")


func test_equip_locked_refused() -> void:
	Cosmetics.request_equip(&"cosmetic_hat_rat_ears")
	assert_false(Cosmetics.get_loadout(_me).has("hat"), "can't wear a locked hat")
	Cosmetics.request_equip(&"cosmetic_hat_hard_hat")
	assert_eq(str(Cosmetics.get_loadout(_me).get("hat", "")), "cosmetic_hat_hard_hat", "a starter hat goes on")
	assert_eq(str(Net.get_record(_me).cosmetic_loadout.get("hat", "")), "cosmetic_hat_hard_hat",
		"and reaches your player record, which everyone gets")
	Cosmetics.request_unequip(&"hat")
	assert_false(Cosmetics.get_loadout(_me).has("hat"), "taken off again")


func test_one_item_per_slot() -> void:
	Cosmetics.request_equip(&"cosmetic_hat_hard_hat")
	Cosmetics.request_equip(&"cosmetic_hat_hairnet")
	Cosmetics.request_equip(&"cosmetic_shoes_clogs")
	var loadout: Dictionary = Cosmetics.get_loadout(_me)
	assert_eq(str(loadout.get("hat", "")), "cosmetic_hat_hairnet", "the new hat replaces the old one")
	assert_eq(str(loadout.get("shoes", "")), "cosmetic_shoes_clogs", "other slots are kept")


func test_unlock_rule_runs_completed() -> void:
	watch_signals(EventBus)
	EventBus.run_ended.emit(&"wiped")
	assert_false(Cosmetics.is_unlocked(&"cosmetic_glasses_sunglasses"), "a wipe isn't an escape")
	EventBus.run_ended.emit(&"escaped")
	assert_true(Cosmetics.is_unlocked(&"cosmetic_glasses_sunglasses"), "escaped once: sunglasses")
	assert_signal_emitted_with_parameters(EventBus, "cosmetic_unlocked", [&"cosmetic_glasses_sunglasses"])
	assert_false(Cosmetics.is_unlocked(&"cosmetic_coat_hi_vis_vest"), "the vest needs 3")
	EventBus.run_ended.emit(&"escaped")
	EventBus.run_ended.emit(&"escaped")
	assert_true(Cosmetics.is_unlocked(&"cosmetic_coat_hi_vis_vest"), "escaped 3 times: the vest")
	assert_eq(Cosmetics.check_unlocks(), [] as Array[StringName], "nothing unlocks twice")


func test_boss_unlock_rule() -> void:
	EventBus.boss_defeated.emit(&"boss_giant_rat")
	await wait_process_frames(2)
	assert_true(Cosmetics.is_unlocked(&"cosmetic_hat_rat_ears"), "beat the Giant Rat: rat ears")
	assert_false(Cosmetics.is_unlocked(&"cosmetic_hat_mushroom_cap"), "not the Mushroom Man's cap")


func test_achievement_unlock_rule() -> void:
	EventBus.floor_task_completed.emit(&"task_hamster_wheel")
	await wait_process_frames(2)
	assert_true(Achievements.is_unlocked(&"achievement_hamster_wheel"), "Cardio Day unlocked")
	assert_true(Cosmetics.is_unlocked(&"cosmetic_hat_sweatband"), "and with it the sweatband")


func test_unlocks_and_outfit_survive_a_restart() -> void:
	Cosmetics.unlock(&"cosmetic_hat_mushroom_cap")
	Cosmetics.request_equip(&"cosmetic_hat_mushroom_cap")
	SaveSystem.use_folder(FOLDER)  # forgets the loaded profile, as if the game started again
	assert_true(Cosmetics.is_unlocked(&"cosmetic_hat_mushroom_cap"), "still unlocked")
	assert_eq(str(SaveSystem.get_profile().loadout.get("hat", "")), "cosmetic_hat_mushroom_cap", "still worn")


func test_dresser_puts_worn_cosmetics_on_the_body() -> void:
	var body: PlayerCharacter = _spawn_me()
	await wait_process_frames(2)
	assert_not_null(_dresser(body), "every player body gets a dresser")
	Cosmetics.request_equip(&"cosmetic_hat_hard_hat")
	await wait_process_frames(2)
	var shown: Dictionary[StringName, Node3D] = _dresser(body).get_shown()
	assert_true(shown.has(&"hat"), "the hat is on")
	assert_eq(shown[&"hat"].get_parent(), body.get_attach_point(&"head"), "on the head")
	assert_false(shown[&"hat"].visible, "your own cosmetics are hidden from you, like the rest of your body")


func test_hidden_slot_not_shown() -> void:
	var body: PlayerCharacter = _spawn_me()
	await wait_process_frames(2)
	Cosmetics.request_equip(&"cosmetic_shoes_clogs")
	await wait_process_frames(2)
	assert_true(_dresser(body).get_shown().has(&"shoes"), "clogs on")
	assert_true(Upgrades.grant(_me, &"mutation_slug"))
	await wait_process_frames(2)
	assert_false(_dresser(body).get_shown().has(&"shoes"), "a Slug can't wear shoes")
	Upgrades.remove(_me, &"mutation_slug")
	await wait_process_frames(2)
	assert_true(_dresser(body).get_shown().has(&"shoes"), "back on once the Slug is gone")


func test_mutation_variant_used() -> void:
	var normal := PackedScene.new()
	var tall := PackedScene.new()
	var data := CosmeticData.new()
	data.scene = normal
	data.mutation_variants = {"mutation_giraffe": tall}
	assert_eq(CosmeticDresser.model_for(data, [] as Array[StringName]), normal, "no mutation: the normal model")
	assert_eq(CosmeticDresser.model_for(data, [&"mutation_giraffe"] as Array[StringName]), tall, "Giraffe: its variant")
	assert_eq(CosmeticDresser.model_for(data, [&"mutation_fly"] as Array[StringName]), normal, "no variant listed")


func test_new_cosmetic_file_needs_no_code() -> void:
	# Every file in content/cosmetics shows up in the closet for its slot: nothing keeps a hand-written list.
	var on_disk: int = 0
	for file: String in DirAccess.get_files_at("res://content/cosmetics"):
		if file.ends_with(".tres") or file.ends_with(".tres.remap"):
			on_disk += 1
	var in_closet: int = 0
	for slot: StringName in CosmeticsService.SLOTS:
		in_closet += Cosmetics.get_all_for_slot(slot).size()
	assert_eq(in_closet, on_disk, "every cosmetic file is in the closet")
	# Cosmetics never change gameplay: CosmeticData has no number fields at all.
	for property: Dictionary in CosmeticData.new().get_property_list():
		if (property["usage"] as int) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			assert_false((property["type"] as int) in [TYPE_INT, TYPE_FLOAT],
				"CosmeticData.%s is not a gameplay number" % property["name"])


func test_closet_tries_on_and_wears() -> void:
	Cosmetics.open_closet()
	await wait_process_frames(2)
	assert_eq(UI.get_open_screen(), CosmeticsService.SCREEN_CLOSET, "the closet opens")
	var closet: ClosetScreen = _closet()
	assert_not_null(closet)
	closet.show_slot(&"hat")
	var texts: PackedStringArray = closet.get_item_texts()
	assert_true(texts.has("Hard hat"), "starter hats are listed: %s" % [texts])
	assert_true(texts.has("Rat ears\n(locked)"), "locked ones say so")
	closet.pick(&"cosmetic_hat_rat_ears")
	assert_string_contains(closet.get_info(), "Beat the Giant Rat", "a locked one says how to get it")
	closet.press_wear()
	assert_false(Cosmetics.get_loadout(_me).has("hat"), "a locked one can't be worn")
	closet.pick(&"cosmetic_hat_hard_hat")
	closet.press_wear()
	assert_eq(str(Cosmetics.get_loadout(_me).get("hat", "")), "cosmetic_hat_hard_hat", "Wear puts it on")
	assert_true(closet.get_item_texts().has("Hard hat\n(worn)"), "and the closet shows it worn")
	closet.press_wear()
	assert_false(Cosmetics.get_loadout(_me).has("hat"), "pressing it again takes it off")
	UI.close_screen()
