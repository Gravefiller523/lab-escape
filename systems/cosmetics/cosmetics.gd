class_name CosmeticsService
extends Node
## Autoload "Cosmetics" (NEW 2026-11-13, roadmap WP17, closet mock-up approved by Zachary): hats, glasses, coats,
## gloves and shoes that only change how you look. Which ones you have unlocked and what you wear are saved in your
## profile on your own PC (SaveSystem). What you wear is sent to the host, kept in your PlayerRecord
## (`cosmetic_loadout`) and synced to everyone, so every PC dresses every player (CosmeticDresser). Cosmetics never
## change gameplay: CosmeticData has no gameplay numbers at all. Spec: docs/systems/cosmetics.md.
##
## Unlock rules (UnlockRuleData.kind): none = from the start; "runs_completed" (escapes, lifetime stat runs_escaped),
## "floors_reached" (best floor), "boss_defeated" (boss_id), "achievement" (achievement_id). They are checked when a
## run ends, a boss is beaten, an achievement unlocks, and when the game starts.
## Console: `unlock_cosmetics` unlocks every one (a cheat for testing the closet).

const SLOTS: Array[StringName] = [&"hat", &"glasses", &"coat", &"gloves", &"shoes"]
## Where each slot sits on the body (PlayerCharacter attach points).
const ATTACH_POINTS: Dictionary[StringName, StringName] = {&"hat": &"head", &"glasses": &"face", &"coat": &"body",
	&"gloves": &"body", &"shoes": &"feet"}
const SCREEN_CLOSET: StringName = &"closet"
const CLOSET_SCENE: PackedScene = preload("res://systems/cosmetics/closet_screen.tscn")


func _ready() -> void:
	UI.register_screen(SCREEN_CLOSET, CLOSET_SCENE)
	EventBus.player_spawned.connect(_on_player_spawned)
	EventBus.run_ended.connect(func(_result: StringName) -> void: check_unlocks())
	EventBus.boss_defeated.connect(func(_boss_id: StringName) -> void: check_unlocks.call_deferred())
	EventBus.achievement_unlocked.connect(func(_achievement_id: StringName) -> void: check_unlocks())
	EventBus.upgrade_gained.connect(func(player_id: int, _upgrade_id: StringName) -> void: _refresh(player_id))
	EventBus.upgrade_lost.connect(func(player_id: int, _upgrade_id: StringName) -> void: _refresh(player_id))
	EventBus.local_player_spawned.connect(func(_body: Node3D) -> void: _send_saved_loadout())
	Net.record_changed.connect(_on_record_changed)
	DebugConsole.register_command(&"unlock_cosmetics", _cmd_unlock_all, "unlock_cosmetics: unlock every cosmetic", true)
	check_unlocks.call_deferred()


## Local: opens the jacket closet screen on this PC (the Break Room's closet calls this for whoever used it).
func open_closet() -> void:
	UI.show_screen(SCREEN_CLOSET)


## Every cosmetic you have: the ones with no unlock rule, plus the ones your profile has unlocked.
func get_unlocked() -> Array[StringName]:
	var found: Array[StringName] = []
	for content: ContentData in ContentRegistry.get_all(&"cosmetic"):
		if is_unlocked(content.id):
			found.append(content.id)
	return found


func is_unlocked(cosmetic_id: StringName) -> bool:
	var data := ContentRegistry.get_content(cosmetic_id) as CosmeticData
	if data == null:
		return false
	return data.unlock == null or SaveSystem.get_profile().unlocked_cosmetic_ids.has(cosmetic_id)


## Every cosmetic for a slot, in id order.
func get_all_for_slot(slot: StringName) -> Array[CosmeticData]:
	var ids: Array[StringName] = ContentRegistry.get_all_ids(&"cosmetic")
	ids.sort()
	var found: Array[CosmeticData] = []
	for id: StringName in ids:
		var data := ContentRegistry.get_content(id) as CosmeticData
		if data != null and data.slot == slot:
			found.append(data)
	return found


## What a player wears: slot -> cosmetic id (from their synced record; your own saved choice for you before the
## host has heard it).
func get_loadout(player_id: int) -> Dictionary:
	var record: PlayerRecord = Net.get_record(player_id)
	if record != null and not record.cosmetic_loadout.is_empty():
		return record.cosmetic_loadout.duplicate()
	if player_id == Net.local_player_id():
		return SaveSystem.get_profile().loadout.duplicate()
	return {}


## Local: wear this (if you have it unlocked). Saved, and sent to the host for everyone.
func request_equip(cosmetic_id: StringName) -> void:
	var data := ContentRegistry.get_content(cosmetic_id) as CosmeticData
	if data == null or not is_unlocked(cosmetic_id):
		return
	var loadout: Dictionary = SaveSystem.get_profile().loadout.duplicate()
	loadout[String(data.slot)] = String(cosmetic_id)
	_save_and_send(loadout)


## Local: take off whatever is in this slot.
func request_unequip(slot: StringName) -> void:
	var loadout: Dictionary = SaveSystem.get_profile().loadout.duplicate()
	loadout.erase(String(slot))
	_save_and_send(loadout)


## Local: unlock one (saves it, tells you).
func unlock(cosmetic_id: StringName) -> void:
	var data := ContentRegistry.get_content(cosmetic_id) as CosmeticData
	var profile: PlayerProfile = SaveSystem.get_profile()
	if data == null or profile.unlocked_cosmetic_ids.has(cosmetic_id):
		return
	profile.unlocked_cosmetic_ids.append(cosmetic_id)
	SaveSystem.save_profile()
	EventBus.cosmetic_unlocked.emit(cosmetic_id)
	EventBus.toast_requested.emit("New in the jacket closet: %s" % data.display_name)


## Local: runs every unlock rule against your profile; unlocks what is now earned. Returns the new ones.
func check_unlocks() -> Array[StringName]:
	var new_ones: Array[StringName] = []
	var profile: PlayerProfile = SaveSystem.get_profile()
	var ids: Array[StringName] = ContentRegistry.get_all_ids(&"cosmetic")
	ids.sort()
	for id: StringName in ids:
		var data := ContentRegistry.get_content(id) as CosmeticData
		if data == null or data.unlock == null or profile.unlocked_cosmetic_ids.has(id):
			continue
		if rule_met(data.unlock):
			unlock(id)
			new_ones.append(id)
	return new_ones


## Is this rule met by your profile and achievements?
func rule_met(rule: UnlockRuleData) -> bool:
	var needed: int = maxi(rule.count, 1)
	match rule.kind:
		&"runs_completed":
			return SaveSystem.get_stat(&"runs_escaped") >= needed
		&"floors_reached":
			return SaveSystem.get_stat(&"floors_reached_best") >= needed
		&"boss_defeated":
			return SaveSystem.get_stat(StringName("boss_defeated:%s" % rule.boss_id)) >= needed
		&"achievement":
			return Achievements.is_unlocked(rule.achievement_id)
	push_warning("Cosmetics: unknown unlock rule '%s'." % rule.kind)
	return false


## What unlocks it, in words (the closet shows this on locked items).
static func describe_unlock(data: CosmeticData) -> String:
	return data.description if data != null else ""


func _save_and_send(loadout: Dictionary) -> void:
	SaveSystem.get_profile().loadout = loadout
	SaveSystem.save_profile()
	_send(loadout)


## Tells the host what you wear (the host stores it in your record, which reaches everyone).
func _send(loadout: Dictionary) -> void:
	if Net.is_host():
		_apply_loadout(Net.local_player_id(), loadout)
	else:
		_loadout_rpc.rpc_id(1, loadout)


## Sends the outfit saved in your profile once your body exists (joining, or the game starting). Nothing changed,
## so nothing is written to disk.
func _send_saved_loadout() -> void:
	var saved: Dictionary = SaveSystem.get_profile().loadout
	var record: PlayerRecord = Net.get_record(Net.local_player_id())
	if record != null and record.cosmetic_loadout == saved:
		_refresh(Net.local_player_id())
		return
	_send(saved.duplicate())


## Client -> host: this is what I wear now.
@rpc("any_peer", "call_remote", "reliable")
func _loadout_rpc(loadout: Dictionary) -> void:
	if not Net.is_host():
		return
	var player_id: int = Net.get_player_id_for_peer(multiplayer.get_remote_sender_id())
	if player_id != 0:
		_apply_loadout(player_id, loadout)


## Host: keep only real cosmetics in the right slots (it trusts unlocks: cosmetics can't change gameplay), then
## store it in the record, which syncs it to everyone.
func _apply_loadout(player_id: int, loadout: Dictionary) -> void:
	var clean: Dictionary = {}
	for slot: Variant in loadout:
		var data := ContentRegistry.get_content(StringName(str(loadout[slot]))) as CosmeticData
		if data != null and String(data.slot) == str(slot):
			clean[str(slot)] = String(data.id)
	if Net.get_record(player_id) == null:
		return
	Net.update_record(player_id, &"cosmetic_loadout", clean)


func _on_record_changed(player_id: int, field: StringName) -> void:
	if field == &"cosmetic_loadout" or field == &"":
		_refresh(player_id)
		EventBus.cosmetics_changed.emit(player_id)


func _on_player_spawned(player_id: int, player_node: Node3D) -> void:
	var body := player_node as PlayerCharacter
	if body == null:
		return
	if body.get_node_or_null(NodePath(CosmeticDresser.NODE_NAME)) == null:
		var dresser := CosmeticDresser.new()
		body.add_child(dresser)
	_refresh(player_id)


func _refresh(player_id: int) -> void:
	var body: PlayerCharacter = PlayerCharacter.find(player_id)
	if body == null:
		return
	var dresser := body.get_node_or_null(NodePath(CosmeticDresser.NODE_NAME)) as CosmeticDresser
	if dresser != null:
		dresser.refresh()


func _cmd_unlock_all(_args: PackedStringArray, _player_id: int) -> String:
	var count: int = 0
	for content: ContentData in ContentRegistry.get_all(&"cosmetic"):
		if not is_unlocked(content.id):
			unlock(content.id)
			count += 1
	return "Unlocked %d cosmetics." % count
