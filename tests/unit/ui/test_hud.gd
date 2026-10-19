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


func _nameplates(plate_range: float = 5.0) -> Nameplates:
	var config := GameConfig.new()
	config.nameplate_range = plate_range
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
	far.position = Vector3(0, 0, -4)
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
