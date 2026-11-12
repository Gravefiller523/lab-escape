extends GutTest
## Tests for the ui HUD and nameplates (docs/systems/ui.md). Solo: every body belongs to this PC, so the
## "other players" are extra bodies with other player ids.

const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")
const LIFT_SCENE: PackedScene = preload("res://systems/cargo_lift/cargo_lift.tscn")
const WAIT: float = 3.0

var _world: SubViewport


func before_each() -> void:
	_world = SubViewport.new()
	_world.own_world_3d = true
	add_child_autofree(_world)


func _body(player_id: int, at: Vector3) -> PlayerCharacter:
	var body := PLAYER_SCENE.instantiate() as PlayerCharacter
	body.player_id = player_id
	body.name = str(player_id)
	body.position = at
	_world.add_child(body)
	return body


## Your eyes: a camera at the origin, looking down -Z.
func _viewer() -> Camera3D:
	var camera := Camera3D.new()
	camera.position = Vector3(0, 1.6, 0)
	_world.add_child(camera)
	camera.make_current()
	return camera


func _nameplates(plate_range: float = 5.0, fade_seconds: float = 0.05) -> Nameplates:
	var config := GameConfig.new()
	config.nameplate_range = plate_range
	config.nameplate_fade_seconds = fade_seconds
	var plates := Nameplates.new()
	plates.use_net(Net, config)
	_world.add_child(plates)
	return plates


func test_lift_text_lists_missing_parts() -> void:
	var missing: Array[String] = ["Lever", "Fuse"]
	var text: String = Hud.lift_text(3, 1, missing, false, false, false)
	assert_string_contains(text, "1/3")
	assert_string_contains(text, "- Lever")
	assert_string_contains(text, "- Fuse")
	var none: Array[String] = []
	assert_string_contains(Hud.lift_text(2, 2, none, false, false, false), "LIFT FIXED")
	assert_string_contains(Hud.lift_text(0, 0, none, true, false, false), "boss")
	assert_eq(Hud.lift_text(2, 0, missing, false, true, false), "", "hidden while riding")
	assert_eq(Hud.lift_text(0, 0, none, false, false, true), "", "hidden in the Break Room")


func test_lift_panel_follows_the_lift() -> void:
	var lift := LIFT_SCENE.instantiate() as CargoLift
	_world.add_child(lift)
	var hud := Hud.new()
	hud.use_sources(null, lift)
	add_child_autofree(hud)
	lift.arrive(2, false)
	await wait_until(func() -> bool: return not hud.get_lift_text().is_empty(), WAIT)
	var text: String = hud.get_lift_text()
	assert_string_contains(text, "0/2")
	for slot: StringName in lift.get_broken_slots():
		assert_string_contains(text, lift.get_slot_part(slot).display_name, "names each missing part")
	lift.arrive(0, true)
	await wait_until(func() -> bool: return hud.get_lift_text().is_empty(), WAIT)
	assert_eq(hud.get_lift_text(), "", "no panel in the Break Room")


func test_prompt_shows_what_you_look_at() -> void:
	var body := _body(Net.local_player_id(), Vector3.ZERO)
	var button := StaticBody3D.new()
	button.collision_layer = PhysicsLayers.bit(PhysicsLayers.INTERACTABLES)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 0.6, 0.2)
	shape.shape = box
	button.add_child(shape)
	button.position = Vector3(0, 1.65, -1.5)
	var use := Interactable.new()
	use.prompt_text = "Pick up crate"
	button.add_child(use)
	_world.add_child(button)
	body.set_input_override(PlayerInputState.new())
	var hud := Hud.new()
	hud.use_sources(InteractionService.controller_of(body), null)
	add_child_autofree(hud)
	await wait_until(func() -> bool: return hud.get_prompt_text() == "E: Pick up crate", WAIT)
	assert_eq(hud.get_prompt_text(), "E: Pick up crate")
	button.position.x = 5.0
	await wait_until(func() -> bool: return hud.get_prompt_text().is_empty(), WAIT)
	assert_eq(hud.get_prompt_text(), "", "nothing to do, no prompt")


func test_names_show_only_within_range() -> void:
	_body(Net.local_player_id(), Vector3.ZERO)
	_body(1001, Vector3(0, 0, -3))
	var far := _body(1002, Vector3(0, 0, -12))
	_viewer()
	var plates := _nameplates()
	await wait_process_frames(3)
	assert_null(plates.get_plate(Net.local_player_id()), "your own name never shows")
	assert_true(plates.is_name_visible(1001), "3 m away: name shows")
	assert_false(plates.is_name_visible(1002), "12 m away: hidden")
	far.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0, -4)))
	await wait_process_frames(3)
	assert_true(plates.is_name_visible(1002), "walked closer: name shows")
	var plate: Node3D = plates.get_plate(1001)
	assert_gt(plate.global_position.y, 1.9, "the name hovers above the head")


func test_speaker_icon_shows_next_to_the_name_while_talking() -> void:
	_body(1001, Vector3(0, 0, -3))
	_viewer()
	var plates := _nameplates()
	await wait_process_frames(3)
	assert_false(plates.is_speaker_visible(1001))
	EventBus.player_speaking_changed.emit(1001, true)
	await wait_process_frames(2)
	assert_true(plates.is_speaker_visible(1001), "talking: speaker icon on")
	var plate: Node3D = plates.get_plate(1001)
	var speaker := plate.get_node(^"Speaker") as Sprite3D
	assert_lt(speaker.position.x, 0.0, "the icon sits beside the name (to its left)")
	EventBus.player_speaking_changed.emit(1001, false)
	await wait_process_frames(2)
	assert_false(plates.is_speaker_visible(1001), "stopped talking: icon off")


func test_plate_goes_when_the_player_leaves() -> void:
	var other := _body(1001, Vector3(0, 0, -3))
	_viewer()
	var plates := _nameplates()
	await wait_process_frames(3)
	assert_not_null(plates.get_plate(1001))
	other.free()
	await wait_process_frames(3)
	assert_null(plates.get_plate(1001))


## NEW 2026-11-11 (roadmap WP2): a dead player (a ghost) shows no name, and gets it back when reprinted.
func test_ghosts_have_no_plate() -> void:
	var other := _body(1001, Vector3(0, 0, -3))
	_viewer()
	var plates := _nameplates()
	await wait_process_frames(3)
	assert_not_null(plates.get_plate(1001), "alive: a name")
	other.set_ghost(true)
	await wait_process_frames(3)
	assert_null(plates.get_plate(1001), "a ghost: no name")
	other.set_ghost(false)
	await wait_process_frames(3)
	assert_not_null(plates.get_plate(1001), "reprinted: the name is back")


func test_names_fade_out_and_back_in() -> void:
	var other := _body(1001, Vector3(0, 0, -3))
	_viewer()
	var plates := _nameplates(5.0, 0.5)
	await wait_until(func() -> bool: return is_equal_approx(plates.get_alpha(1001), 1.0), WAIT)
	assert_almost_eq(plates.get_alpha(1001), 1.0, 0.001, "close: fully shown")
	other.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0, -10)))
	await wait_process_frames(3)
	assert_between(plates.get_alpha(1001), 0.01, 0.99, "walking away: fading, not gone at once")
	assert_true(plates.is_name_visible(1001))
	await wait_until(func() -> bool: return not plates.is_name_visible(1001), WAIT)
	assert_false(plates.is_name_visible(1001), "faded away")
	other.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0, -3)))
	await wait_process_frames(3)
	assert_between(plates.get_alpha(1001), 0.01, 0.99, "coming back: fading in")
	await wait_until(func() -> bool: return is_equal_approx(plates.get_alpha(1001), 1.0), WAIT)
	assert_almost_eq(plates.get_alpha(1001), 1.0, 0.001, "fully back")


# --- NEW 2026-11-11 (roadmap WP5): the rest of the HUD ------------------------------------------------------

func _target_with_health(max_health: float = 100.0) -> Node3D:
	var target := Node3D.new()
	_world.add_child(target)
	DamageService.give_components(target, max_health)
	return target


func test_the_hud_has_every_widget() -> void:
	var hud := Hud.new()
	add_child_autofree(hud)
	assert_not_null(hud.health_bar, "health bar")
	assert_eq(hud.health_bar.get_parent().name, &"HealthSlot", "in the bottom-left spot")
	assert_not_null(hud.inventory_bar, "inventory bar")
	assert_eq(hud.inventory_bar.get_parent().name, &"InventorySlot", "in the bottom-middle spot")
	assert_not_null(hud.boss_bar, "boss bar")
	assert_not_null(hud.player_list, "player list")
	assert_not_null(hud.ghost_panel, "ghost panel")
	assert_not_null(hud.run_summary, "run summary")


func test_health_bar_shows_health_and_statuses() -> void:
	var target: Node3D = _target_with_health(100.0)
	var bar := HealthBar.new()
	bar.use_body(target)
	_world.add_child(bar)
	await wait_process_frames(2)
	assert_eq(bar.get_text(), "100 / 100")
	HealthComponent.of(target).apply_damage(DamageInfo.make(28.0, &"blunt"))
	await wait_process_frames(2)
	assert_eq(bar.get_text(), "72 / 100", "28 damage")
	StatusEffectComponent.of(target).apply(&"status_burning")
	await wait_process_frames(2)
	assert_eq(bar.get_status_texts().size(), 1, "one status chip")
	assert_string_contains(bar.get_status_texts()[0], "s", "with the seconds left")
	HealthComponent.of(target).apply_damage(DamageInfo.make(500.0, &"blunt"))
	await wait_process_frames(2)
	assert_eq(bar.get_text(), "", "hidden once you're dead (the ghost screen takes over)")


func test_inventory_bar_shows_slots_and_what_you_hold() -> void:
	var body := Node3D.new()
	_world.add_child(body)
	var inventory := InventoryComponent.new()
	body.add_child(inventory)
	var bar := InventoryBar.new()
	bar.use_body(body)
	_world.add_child(bar)
	await wait_process_frames(2)
	assert_eq(bar.get_slot_texts().size(), inventory.get_slot_count(), "one box per slot")
	assert_true(inventory.add_item(&"item_crowbar"))
	await wait_process_frames(2)
	assert_string_contains(bar.get_slot_texts()[0], "Crowbar", "the crowbar is in slot 1")
	assert_true(bar.get_slot_texts()[0].begins_with(">"), "slot 1 is selected")
	assert_string_contains(bar.get_held_text(), "Crowbar", "and in your hands")
	inventory.set_bonus_slots(&"mutation_octo", 1)
	await wait_process_frames(2)
	assert_eq(bar.get_slot_texts().size(), inventory.get_slot_count(), "an extra slot gets a box too")


func test_ghost_panel_tells_you_how_to_come_back() -> void:
	var panel := GhostPanel.new()
	_world.add_child(panel)
	panel.use_state(0, 0)
	await wait_process_frames(2)
	assert_eq(panel.get_text(), "", "alive: nothing")
	panel.use_state(1, 0)
	await wait_process_frames(2)
	assert_string_contains(panel.get_text(), "ghost")
	panel.use_state(0, 1)
	await wait_process_frames(2)
	assert_string_contains(panel.get_text(), "next floor", "a mid-run joiner hears when they'll spawn")


func test_player_list_has_a_line_per_player() -> void:
	var list := PlayerList.new()
	_world.add_child(list)
	await wait_process_frames(2)
	assert_eq(list.get_lines().size(), Net.get_player_ids().size(), "one line per player in the game")
	EventBus.player_speaking_changed.emit(Net.local_player_id(), true)
	await wait_process_frames(2)
	assert_string_contains(list.get_lines()[0], "speaking")
	EventBus.player_speaking_changed.emit(Net.local_player_id(), false)


func test_run_summary_counts_the_run() -> void:
	var summary := RunSummaryPanel.new()
	_world.add_child(summary)
	summary.show_now()
	var me: int = Net.local_player_id()
	EventBus.run_started.emit(1)
	EventBus.player_died.emit(me, Vector3.ZERO)
	EventBus.vendor_purchase.emit(me, &"item_crowbar", 3)
	EventBus.run_ended.emit(&"escaped")
	await wait_process_frames(2)
	assert_string_contains(summary.get_text(), "Escaped")
	assert_string_contains(summary.get_text(), "0 floors", "no floor was reached in this test")
	var rows: PackedStringArray = summary.get_rows()
	assert_gt(rows.size(), 0, "a row for you")
	assert_string_contains(rows[0], "| 1 | 3 |", "1 death, 3 gems spent")


## NEW 2026-11-11 (roadmap WP7): getting hurt reddens the screen edges, then they fade.
func test_hurt_vignette_flashes_and_fades() -> void:
	var target: Node3D = _target_with_health(100.0)
	var vignette := HurtVignette.new()
	vignette.use_body(target)
	add_child_autofree(vignette)
	await wait_process_frames(2)
	assert_eq(vignette.get_strength(), 0.0, "nothing before a hit")
	HealthComponent.of(target).apply_damage(DamageInfo.make(10.0, &"blunt"))
	await wait_process_frames(2)
	assert_gt(vignette.get_strength(), 0.0, "red edges after a hit")
	await wait_seconds(Config.feel.hits.hurt_vignette_seconds + 0.2)
	assert_eq(vignette.get_strength(), 0.0, "faded out")
