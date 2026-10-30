extends GutTest
## Tests for interaction (docs/systems/interaction.md). Solo tests use the real player body (it's the
## host and the local player at once); the network test uses two "PCs" over real ENet.

const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")
const PORT: int = 18010
const WAIT: float = 5.0

var _world: Node3D


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)


## A local body standing at the origin, looking down -Z, with its controller.
func _body(parent: Node3D = null, player_id: int = 7) -> PlayerCharacter:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	(parent if parent != null else _world).add_child(floor_body)
	var body := PLAYER_SCENE.instantiate() as PlayerCharacter
	body.player_id = player_id
	body.name = str(player_id)
	(parent if parent != null else _world).add_child(body)
	return body


## A button in front of the player's eyes, `distance` metres away.
func _button(distance: float, parent: Node3D = null, prompt: String = "Press button", hold: float = 0.0) -> Interactable:
	var button := StaticBody3D.new()
	button.name = "Button%d" % int(distance * 10.0)
	button.collision_layer = PhysicsLayers.bit(PhysicsLayers.INTERACTABLES)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 0.6, 0.2)
	shape.shape = box
	button.add_child(shape)
	button.position = Vector3(0, 1.65, -distance)
	var interactable := Interactable.new()
	interactable.name = "Interactable"
	interactable.prompt_text = prompt
	interactable.hold_seconds = hold
	button.add_child(interactable)
	(parent if parent != null else _world).add_child(button)
	return interactable


func _controller(body: PlayerCharacter) -> InteractionController:
	return InteractionService.controller_of(body)


func test_controller_added_to_every_body() -> void:
	var body := _body()
	assert_not_null(_controller(body), "the Interaction autoload gave the body a controller")


func test_target_found_by_ray() -> void:
	var body := _body()
	var button := _button(1.5)
	body.set_input_override(PlayerInputState.new())
	await wait_physics_frames(5)
	assert_eq(_controller(body).get_target(), button.get_parent())
	assert_eq(_controller(body).get_prompt(), "Press button")


func test_press_fires_used_on_host_with_player_id() -> void:
	var body := _body(null, 42)
	var button := _button(1.5)
	body.set_input_override(PlayerInputState.new())
	await wait_physics_frames(5)
	watch_signals(button)
	_controller(body).press_use(_controller(body).get_target())
	assert_signal_emitted_with_parameters(button, "used", [42])


func test_out_of_range_rejected_on_host() -> void:
	var body := _body()
	var far := _button(3.6)
	far.max_distance = 1.0
	await wait_physics_frames(5)
	watch_signals(far)
	_controller(body).request_use(far.get_anchor(), 0.0)
	assert_signal_not_emitted(far, "used", "too far away")
	assert_eq(_controller(body).get_prompt(), "", "no prompt when out of reach")


func test_hold_requires_full_time() -> void:
	var body := _body()
	var lever := _button(1.5, null, "Pull lever", 1.0)
	await wait_physics_frames(2)
	watch_signals(lever)
	_controller(body).request_use(lever.get_anchor(), 0.5)
	assert_signal_not_emitted(lever, "used", "not held long enough")
	_controller(body).request_use(lever.get_anchor(), 1.0)
	assert_signal_emitted(lever, "used")


func test_use_condition_blocks() -> void:
	var body := _body()
	var button := _button(1.5)
	button.use_condition = func(_player_id: int) -> bool: return false
	await wait_physics_frames(2)
	watch_signals(button)
	_controller(body).request_use(button.get_anchor(), 0.0)
	assert_signal_not_emitted(button, "used")
	button.use_condition = Callable()
	button.enabled = false
	_controller(body).request_use(button.get_anchor(), 0.0)
	assert_signal_not_emitted(button, "used", "disabled")


func test_handler_priority_order() -> void:
	var body := _body()
	var button := _button(1.5)
	await wait_physics_frames(2)
	var calls: Array[String] = []
	var controller := _controller(body)
	controller.register_use_handler(1, func(_target: Node3D) -> bool:
		calls.append("low")
		return false)
	controller.register_use_handler(10, func(_target: Node3D) -> bool:
		calls.append("high")
		return true)
	watch_signals(button)
	controller.press_use(button.get_anchor())
	assert_eq(calls, ["high"] as Array[String], "the higher priority ran first and took the press")
	assert_signal_not_emitted(button, "used", "the Interactable never got it")


func test_prompt_provider_overrides_text() -> void:
	var body := _body()
	_button(1.5)
	body.set_input_override(PlayerInputState.new())
	await wait_physics_frames(5)
	var controller := _controller(body)
	controller.register_prompt_provider(5, func(_target: Node3D) -> String: return "Grab box")
	assert_eq(controller.get_prompt(), "Grab box")
	controller.register_prompt_provider(9, func(_target: Node3D) -> String: return "")
	assert_eq(controller.get_prompt(), "Grab box", "an empty answer means no opinion")


# --- HL2 feel step 4.1 (NEW 2026-10-30) ---

## FIX 2026-10-30 (found by Zachary): the thing you look at is removed, then you press E before the next physics
## step: no error, it just counts as looking at nothing.
func test_pressing_use_right_after_the_target_is_removed_is_safe() -> void:
	var body := _body()
	var button := _button(1.5)
	body.set_input_override(PlayerInputState.new())
	await wait_physics_frames(5)
	assert_eq(_controller(body).get_target(), button.get_parent())
	button.get_parent().free()
	assert_null(_controller(body).get_target(), "the removed thing is forgotten")
	assert_eq(_controller(body).get_prompt(), "")
	var press := InputEventAction.new()
	press.action = InputActions.USE
	press.pressed = true
	_controller(body)._unhandled_input(press)
	assert_true(true, "pressing E did not crash")


func test_pressing_use_on_nothing_buzzes() -> void:
	var body := _body()
	await wait_physics_frames(2)
	watch_signals(EventBus)
	assert_false(_controller(body).press_use(null), "nothing took the press")
	assert_signal_emitted_with_parameters(EventBus, "use_denied", [7])


func test_a_refused_use_buzzes_and_tells_the_object() -> void:
	var body := _body()
	var button := _button(1.5)
	button.use_condition = func(_player_id: int) -> bool: return false
	await wait_physics_frames(2)
	watch_signals(EventBus)
	watch_signals(button)
	_controller(body).request_use(button.get_anchor(), 0.0)
	assert_signal_emitted_with_parameters(EventBus, "use_denied", [7])
	assert_signal_emitted_with_parameters(button, "refused", [7])


func test_reach_is_measured_to_the_use_point() -> void:
	var body := _body()
	var far := _button(3.0)
	far.max_distance = 1.0
	var point := Marker3D.new()
	point.name = "Point"
	point.position = Vector3(0, 0, 2.5)
	far.get_anchor().add_child(point)
	far.use_point = NodePath("../Point")
	await wait_physics_frames(2)
	watch_signals(far)
	_controller(body).request_use(far.get_anchor(), 0.0)
	assert_signal_emitted(far, "used", "its handle is close enough, though the object is 3 m away")


func test_aim_helper_finds_a_tiny_button_just_beside_the_crosshair() -> void:
	var body := _body()
	body.set_input_override(PlayerInputState.new())
	await wait_physics_frames(5)
	var tiny := _tiny_button(body.get_aim_origin() + Vector3(0.1, 0, -1.5))
	await wait_physics_frames(3)
	assert_eq(_controller(body).get_target(), tiny, "the thin ray misses it, the ball finds it")


func test_aim_helper_never_sees_through_a_wall() -> void:
	var body := _body()
	body.set_input_override(PlayerInputState.new())
	await wait_physics_frames(5)
	var eyes: Vector3 = body.get_aim_origin()
	var wall := StaticBody3D.new()
	wall.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 3, 0.2)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(eyes.x, 1.5, eyes.z - 1.0)
	_world.add_child(wall)
	_tiny_button(eyes + Vector3(0.1, 0, -1.5))
	await wait_physics_frames(3)
	assert_eq(_controller(body).get_target(), wall, "it sees the wall, not the button behind it")


func test_continuous_use_ticks_on_the_host_until_let_go() -> void:
	var body := _body()
	var valve := _button(1.5, null, "Turn valve")
	valve.continuous = true
	await wait_physics_frames(2)
	var ticks: Array[float] = []
	valve.use_tick.connect(func(_player_id: int, delta: float) -> void: ticks.append(delta))
	watch_signals(valve)
	var controller := _controller(body)
	assert_true(controller.press_use(valve.get_anchor()), "pressing a continuous object takes the press (no buzz)")
	controller.set_continuous_use(valve.get_anchor())
	await wait_physics_frames(10)
	assert_signal_emitted_with_parameters(valve, "use_started", [7])
	assert_gt(ticks.size(), 5, "it ticks every physics step while held")
	controller.set_continuous_use(null)
	assert_signal_emitted_with_parameters(valve, "use_stopped", [7])
	var count: int = ticks.size()
	await wait_physics_frames(5)
	assert_eq(ticks.size(), count, "and stops when let go")
	controller.set_continuous_use(valve.get_anchor())
	await wait_physics_frames(3)
	body.global_position = Vector3(0, 0, 8)
	await wait_physics_frames(3)
	count = ticks.size()
	await wait_physics_frames(3)
	assert_eq(ticks.size(), count, "walking out of reach stops it too")


## A 4 cm button (a plain StaticBody3D with an Interactable) at `where`.
func _tiny_button(where: Vector3) -> StaticBody3D:
	var button := StaticBody3D.new()
	button.name = "Tiny"
	button.collision_layer = PhysicsLayers.bit(PhysicsLayers.INTERACTABLES)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.04, 0.04, 0.04)
	shape.shape = box
	button.add_child(shape)
	button.position = where
	var interactable := Interactable.new()
	button.add_child(interactable)
	_world.add_child(button)
	return button


func test_client_use_goes_through_the_host() -> void:
	# Two PCs, each with its own world, Net and Players container (paths match on both).
	var host_pc := _pc()
	var client_pc := _pc()
	var server := ENetMultiplayerPeer.new()
	assert_eq(server.create_server(PORT, 4), OK)
	host_pc.multiplayer.multiplayer_peer = server
	var client_peer := ENetMultiplayerPeer.new()
	client_peer.create_client("127.0.0.1", PORT)
	client_pc.multiplayer.multiplayer_peer = client_peer
	var client_net := client_pc.get_node("Net") as NetService
	await wait_until(func() -> bool: return client_pc.get_node("Players").get_child_count() >= 3, WAIT)
	var client_id: int = client_net.local_player_id()
	var host_button := host_pc.get_node("Players/Button15/Interactable") as Interactable
	await wait_until(func() -> bool: return host_pc.get_node_or_null("Players/%d" % client_id) != null, WAIT)
	var client_body := client_pc.get_node("Players/%d" % client_id) as PlayerCharacter
	await wait_physics_frames(5)
	watch_signals(host_button)
	_controller(client_body).request_use(client_pc.get_node("Players/Button15") as Node3D, 0.0)
	await wait_until(func() -> bool: return get_signal_emit_count(host_button, "used") > 0, WAIT)
	assert_signal_emitted_with_parameters(host_button, "used", [client_id])
	for pc: Node in [host_pc, client_pc]:
		var path: NodePath = pc.get_path()
		var peer: MultiplayerPeer = pc.multiplayer.multiplayer_peer
		pc.free()
		peer.close()
		get_tree().set_multiplayer(null, path)


## One "PC": its own physics, multiplayer, Net, and a Players container with a spawner and a button.
func _pc() -> Node:
	var pc := SubViewport.new()
	pc.own_world_3d = true
	pc.name = "Pc%d" % get_child_count()
	add_child(pc)
	get_tree().set_multiplayer(SceneMultiplayer.new(), pc.get_path())
	var net := NetService.new()
	net.name = "Net"
	pc.add_child(net)
	var players := Node3D.new()
	players.name = "Players"
	pc.add_child(players)
	var spawner := PlayerSpawner.new()
	spawner.name = "PlayerSpawner"
	spawner.use_net(net)
	players.add_child(spawner)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	players.add_child(floor_body)
	var button := _button(1.5, players)
	button.max_distance = 30.0
	return pc
