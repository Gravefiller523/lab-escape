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
	_controller(body).request_use(far.get_parent(), 0.0)
	assert_signal_not_emitted(far, "used", "too far away")
	assert_eq(_controller(body).get_prompt(), "", "no prompt when out of reach")


func test_hold_requires_full_time() -> void:
	var body := _body()
	var lever := _button(1.5, null, "Pull lever", 1.0)
	await wait_physics_frames(2)
	watch_signals(lever)
	_controller(body).request_use(lever.get_parent(), 0.5)
	assert_signal_not_emitted(lever, "used", "not held long enough")
	_controller(body).request_use(lever.get_parent(), 1.0)
	assert_signal_emitted(lever, "used")


func test_use_condition_blocks() -> void:
	var body := _body()
	var button := _button(1.5)
	button.use_condition = func(_player_id: int) -> bool: return false
	await wait_physics_frames(2)
	watch_signals(button)
	_controller(body).request_use(button.get_parent(), 0.0)
	assert_signal_not_emitted(button, "used")
	button.use_condition = Callable()
	button.enabled = false
	_controller(body).request_use(button.get_parent(), 0.0)
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
	controller.press_use(button.get_parent())
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
