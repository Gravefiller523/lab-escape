extends GutTest
## Tests for the world wiring kit (docs/systems/world_io.md, NEW 2026-10-30, HL2 feel step 4.2). Solo
## tests use a real player body, which is the host and the local player at once; the last test uses two
## "PCs" over real ENet to check other PCs see doors move.

const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")
const PORT: int = 18030
const WAIT: float = 5.0

var _world: Node3D


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)
	_add_floor(_world)


func _add_floor(parent: Node3D) -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	parent.add_child(floor_body)


## A local player body standing at `at`, looking down -Z, keeping still.
func _body(at: Vector3, player_id: int = 7) -> PlayerCharacter:
	var body := PLAYER_SCENE.instantiate() as PlayerCharacter
	body.player_id = player_id
	body.name = str(player_id)
	_world.add_child(body)
	body.global_position = at
	body.set_input_override(PlayerInputState.new())
	return body


func _controller(body: PlayerCharacter) -> InteractionController:
	return InteractionService.controller_of(body)


## A door with its hinge at `at`, running along +X.
func _door(at: Vector3 = Vector3.ZERO, locked: bool = false) -> WorldDoor:
	var door := WorldDoor.new()
	door.name = "Door"
	door.locked = locked
	door.position = at
	_world.add_child(door)
	return door


## Did this device fire `event` (set off by `activator`) at any point since watch_signals?
func _fired(device: WorldDevice, event: StringName, activator: int) -> bool:
	for index: int in get_signal_emit_count(device, "output_fired"):
		var params: Array = get_signal_parameters(device, "output_fired", index)
		if params[0] == event and params[1] == activator:
			return true
	return false


func _wait_until_still(door: WorldDoor) -> void:
	await wait_until(func() -> bool: return door.get_angle() == door.get_target_angle(), WAIT)


func test_a_wire_waits_its_delay_and_once_means_once() -> void:
	var first := WorldRelay.new()
	var second := WorldRelay.new()
	_world.add_child(first)
	_world.add_child(second)
	first.wire(&"triggered", second, &"trigger", 0.2, true)
	watch_signals(second)
	first.receive(&"trigger")
	assert_signal_not_emitted(second, "output_fired", "not before the delay")
	await wait_seconds(0.4)
	assert_signal_emit_count(second, "output_fired", 1, "after the delay")
	first.receive(&"trigger")
	await wait_seconds(0.4)
	assert_signal_emit_count(second, "output_fired", 1, "a once wire runs only the first time")


func test_pressing_a_wired_button_opens_the_door() -> void:
	var door := _door()
	var button := WorldButton.new()
	button.position = Vector3(1.8, 1.3, 0.2)
	_world.add_child(button)
	button.wire(&"pressed", door, &"open")
	var body := _body(Vector3(0.6, 0, 1.6))
	await wait_physics_frames(5)
	_controller(body).request_use(button.get_node("Body") as Node3D, 0.0)
	assert_true(button.is_pressed(), "the button went in")
	assert_gt(door.get_target_angle(), 0.0, "the door opens, away from whoever pressed the button")
	await _wait_until_still(door)
	assert_true(door.is_open())
	await wait_seconds(1.2)
	assert_false(button.is_pressed(), "it popped back out after reset_seconds")


func test_a_door_swings_away_from_whoever_opens_it() -> void:
	var door := _door()
	var body := _body(Vector3(0.6, 0, 1.4))
	await wait_physics_frames(5)
	var panel := door.get_node("Panel") as Node3D
	_controller(body).request_use(panel, 0.0)
	assert_almost_eq(door.get_target_angle(), door.swing_degrees, 0.01, "from the +Z side it swings towards -Z")
	await _wait_until_still(door)
	door.close()
	await _wait_until_still(door)
	body.global_position = Vector3(0.6, 0, -1.4)
	await wait_physics_frames(5)
	_controller(body).request_use(panel, 0.0)
	assert_almost_eq(door.get_target_angle(), -door.swing_degrees, 0.01, "from the -Z side it swings towards +Z")


func test_a_closing_door_goes_back_when_a_player_is_in_the_way() -> void:
	var door := _door()
	door.open()
	await _wait_until_still(door)
	# Open (+95 degrees) it lies along -Z; shutting sweeps the corner with x > 0 and z < 0. Stand in it.
	_body(Vector3(0.75, 0, -0.65))
	await wait_physics_frames(5)
	watch_signals(door)
	door.close()
	await wait_until(func() -> bool: return door.get_target_angle() != 0.0, WAIT)
	assert_true(_fired(door, &"blocked", 0), "fired blocked")
	assert_gt(door.get_target_angle(), 0.0, "it goes back open")
	assert_gt(door.get_angle(), 20.0, "it never swung through the player")


func test_a_locked_door_buzzes_and_reports_the_try() -> void:
	var door := _door(Vector3.ZERO, true)
	var body := _body(Vector3(0.6, 0, 1.4))
	await wait_physics_frames(5)
	watch_signals(EventBus)
	watch_signals(door)
	_controller(body).request_use(door.get_node("Panel") as Node3D, 0.0)
	assert_eq(door.get_target_angle(), 0.0, "it stays shut")
	assert_signal_emitted_with_parameters(EventBus, "use_denied", [7])
	assert_true(_fired(door, &"locked_use", 7), "fired locked_use")
	assert_eq(door.get_interactable().prompt_text, "Locked door")
	door.receive(&"unlock")
	_controller(body).request_use(door.get_node("Panel") as Node3D, 0.0)
	assert_ne(door.get_target_angle(), 0.0, "unlocked, it opens")


func test_a_trigger_fires_when_a_player_walks_in_and_out() -> void:
	var trigger := WorldTrigger.new()
	trigger.position = Vector3(5, 1, 0)
	_world.add_child(trigger)
	var body := _body(Vector3(0, 0, 5))
	await wait_physics_frames(5)
	watch_signals(trigger)
	body.global_position = Vector3(5, 0, 0)
	await wait_until(func() -> bool: return get_signal_emit_count(trigger, "output_fired") > 0, WAIT)
	assert_true(_fired(trigger, &"entered", 7), "fired entered")
	body.global_position = Vector3(0, 0, 5)
	await wait_until(func() -> bool: return get_signal_emit_count(trigger, "output_fired") > 1, WAIT)
	assert_true(_fired(trigger, &"exited", 7), "fired exited")


func test_a_counter_reaches_its_goal_once() -> void:
	var counter := WorldCounter.new()
	counter.goal = 2
	_world.add_child(counter)
	var relay := WorldRelay.new()
	_world.add_child(relay)
	relay.wire(&"triggered", counter, &"add")
	watch_signals(counter)
	relay.receive(&"trigger")
	assert_eq(counter.get_count(), 1)
	relay.receive(&"trigger")
	relay.receive(&"trigger")
	assert_eq(counter.get_count(), 3)
	assert_true(_fired(counter, &"reached", 0), "fired reached")
	counter.receive(&"reset")
	assert_eq(counter.get_count(), 0)
	assert_true(_fired(counter, &"left", 0), "fired left")


func test_a_disabled_device_ignores_inputs_until_enabled() -> void:
	var door := _door()
	door.receive(&"disable")
	door.receive(&"open")
	assert_eq(door.get_target_angle(), 0.0, "disabled: it ignores open")
	assert_false(door.get_interactable().enabled, "and has no prompt")
	door.receive(&"enable")
	door.receive(&"open")
	assert_ne(door.get_target_angle(), 0.0, "enabled again: it opens")


func test_a_valve_turns_while_held_and_turns_back_when_let_go() -> void:
	var crank := WorldCrank.new()
	crank.turn_seconds = 1.0
	crank.rewind_seconds = 1.0
	crank.position = Vector3(0, 1.4, -1.0)
	_world.add_child(crank)
	var body := _body(Vector3.ZERO)
	await wait_physics_frames(5)
	watch_signals(crank)
	var wheel := crank.get_node("Body") as Node3D
	_controller(body).set_continuous_use(wheel)
	await wait_seconds(0.5)
	var turned: float = crank.get_progress()
	assert_between(turned, 0.25, 0.8, "about half way after half the time (%.2f)" % turned)
	assert_true(_fired(crank, &"started", 7), "fired started")
	_controller(body).set_continuous_use(null)
	await wait_seconds(0.25)
	assert_lt(crank.get_progress(), turned, "let go, it turns back")
	_controller(body).set_continuous_use(wheel)
	await wait_until(func() -> bool: return crank.is_done(), WAIT)
	assert_true(_fired(crank, &"completed", 7), "fired completed")
	_controller(body).set_continuous_use(null)
	await wait_seconds(0.3)
	assert_eq(crank.get_progress(), 1.0, "done for good: it stays turned")


func test_other_pcs_see_doors_move_and_joiners_get_the_state() -> void:
	var host_pc := _pc()
	var client_pc := _pc()
	var server := ENetMultiplayerPeer.new()
	assert_eq(server.create_server(PORT, 4), OK)
	host_pc.multiplayer.multiplayer_peer = server
	# The host's second door opens before the client has joined: the client must ask for it.
	var host_first := _pc_door(host_pc, "First")
	var host_second := _pc_door(host_pc, "Second")
	await wait_physics_frames(2)
	host_second.receive(&"open")
	var client_peer := ENetMultiplayerPeer.new()
	client_peer.create_client("127.0.0.1", PORT)
	client_pc.multiplayer.multiplayer_peer = client_peer
	await wait_until(func() -> bool: return client_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, WAIT)
	var client_first := _pc_door(client_pc, "First")
	var client_second := _pc_door(client_pc, "Second")
	await wait_until(func() -> bool: return client_second.get_target_angle() != 0.0, WAIT)
	assert_eq(client_second.get_target_angle(), host_second.get_target_angle(), "a door built after it opened asks the host")
	await wait_physics_frames(5)
	host_first.receive(&"open")
	await wait_until(func() -> bool: return client_first.get_target_angle() != 0.0, WAIT)
	assert_eq(client_first.get_target_angle(), host_first.get_target_angle(), "the client's door heads the same way")
	await wait_until(func() -> bool: return client_first.is_open(), WAIT)
	assert_true(client_first.is_open(), "and swings open there too")
	for pc: Node in [host_pc, client_pc]:
		var path: NodePath = pc.get_path()
		var peer: MultiplayerPeer = pc.multiplayer.multiplayer_peer
		pc.free()
		peer.close()
		get_tree().set_multiplayer(null, path)


## One "PC": its own physics and multiplayer, and a Level node for its doors.
func _pc() -> Node:
	var pc := SubViewport.new()
	pc.own_world_3d = true
	pc.name = "Pc%d" % get_child_count()
	add_child(pc)
	get_tree().set_multiplayer(SceneMultiplayer.new(), pc.get_path())
	var level := Node3D.new()
	level.name = "Level"
	pc.add_child(level)
	_add_floor(level)
	return pc


func _pc_door(pc: Node, door_name: String) -> WorldDoor:
	var door := WorldDoor.new()
	door.name = door_name
	pc.get_node("Level").add_child(door)
	return door
