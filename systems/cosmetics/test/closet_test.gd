extends Node3D
## Test scene for cosmetics (NEW 2026-11-13, roadmap WP17). Press F6 on closet_test.tscn: the jacket closet opens on
## its own, with a profile in a test folder so your real unlocks and outfit are never touched.
## Keys: F1 unlocks every cosmetic, F2 toggles the Slug mutation (no shoes), F3 toggles the Giraffe mutation,
## C reopens the closet after closing it.

const FOLDER: String = "user://test_cosmetics_scene"


func _ready() -> void:
	SaveSystem.use_folder(FOLDER)
	Cosmetics.open_closet()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var me: int = Net.local_player_id()
	match key.keycode:
		KEY_F1:
			for content: ContentData in ContentRegistry.get_all(&"cosmetic"):
				Cosmetics.unlock(content.id)
			_reopen()
		KEY_F2:
			_toggle(me, &"mutation_slug")
		KEY_F3:
			_toggle(me, &"mutation_giraffe")
		KEY_C:
			_reopen()


func _toggle(player_id: int, upgrade_id: StringName) -> void:
	if Upgrades.has_upgrade(player_id, upgrade_id):
		Upgrades.remove(player_id, upgrade_id)
	else:
		Upgrades.grant(player_id, upgrade_id)
	_reopen()


func _reopen() -> void:
	Cosmetics.open_closet()
