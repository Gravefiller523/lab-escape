extends GutTest
## Tests for carts (docs/systems/carts.md). Solo: this PC is the host, with a floor, a PropSpawner, a cart
## and a player. Props are spawned above the basket so they fall in.

const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")
const WAIT: float = 5.0

var _world: Node3D
var _body: PlayerCharacter
var _cart: Cart


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	_world.add_child(floor_body)
	var props := PropSpawner.new()
	props.name = "Props"
	_world.add_child(props)
	_body = PLAYER_SCENE.instantiate() as PlayerCharacter
	_body.player_id = Net.local_player_id()
	_body.name = str(_body.player_id)
	_body.position = Vector3(0, 0, 3)
	_world.add_child(_body)
	_body.set_input_override(PlayerInputState.new())
	_cart = Props.spawn_prop(&"prop_cart_standard", Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0))) as Cart
	await wait_physics_frames(10)


func _drop_in(prop_id: StringName, offset: Vector3 = Vector3.ZERO) -> NetProp:
	return Props.spawn_prop(prop_id, Transform3D(Basis.IDENTITY, _cart.global_position + Vector3(0, 1.4, 0) + offset))


func test_cart_spawns_as_a_cart() -> void:
	assert_not_null(_cart, "the cart prop's scene root is a Cart")
	assert_eq(_cart.collision_layer, PhysicsLayers.bit(PhysicsLayers.CARTS))


func test_prop_snaps_in_and_freezes() -> void:
	var gem: NetProp = _drop_in(&"prop_gem")
	await wait_until(func() -> bool: return _cart.has_prop(gem), WAIT)
	assert_true(_cart.has_prop(gem), "it fell into the basket and snapped in")
	assert_true(gem.is_attached())
	assert_true(gem.freeze, "frozen: it can't bounce out")
	_cart.apply_central_impulse(Vector3(0, 0, -60))
	await wait_physics_frames(20)
	assert_lt(gem.global_position.distance_to(_cart.global_position), 1.2, "it rides along")


func test_grab_out_detaches() -> void:
	var gem: NetProp = _drop_in(&"prop_gem")
	await wait_until(func() -> bool: return _cart.has_prop(gem), WAIT)
	_cart.request_take_out(gem)
	assert_false(_cart.has_prop(gem))
	assert_false(gem.is_attached(), "physics back on")


func test_e_on_a_prop_in_the_cart_takes_it_out_into_your_hands() -> void:
	var gem: NetProp = _drop_in(&"prop_gem")
	await wait_until(func() -> bool: return _cart.has_prop(gem), WAIT)
	var controller: InteractionController = InteractionService.controller_of(_body)
	assert_true(controller.press_use(gem))
	await wait_until(func() -> bool: return gem.is_held(), WAIT)
	assert_true(gem.is_held(), "out of the cart and in your hands")
	assert_false(_cart.has_prop(gem))


func test_capacity_from_config() -> void:
	var saved: int = Config.game.cart_capacity
	Config.game.cart_capacity = 3
	assert_eq(_cart.get_capacity(), 3)
	for index: int in 5:
		_drop_in(&"prop_gem", Vector3(0.1 * float(index), 0.3 * float(index), 0))
	await wait_physics_frames(60)
	assert_eq(_cart.get_contents().size(), 3, "full at 3")
	Config.game.cart_capacity = saved


func test_second_pusher_refused() -> void:
	_cart.request_push(true)
	assert_eq(_cart.get_pusher_id(), _body.player_id)
	_cart._set_pusher(9999, true)
	assert_eq(_cart.get_pusher_id(), _body.player_id, "someone is already pushing")
	_cart.request_push(false)
	assert_eq(_cart.get_pusher_id(), 0)


func test_pushing_moves_the_cart() -> void:
	var start: Vector3 = _cart.global_position
	var controller: InteractionController = InteractionService.controller_of(_body)
	assert_true(controller.press_use(_cart), "E on the cart pushes it")
	assert_eq(_cart.get_pusher_id(), _body.player_id)
	_body.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0.1, -2)))
	await wait_physics_frames(60)
	assert_gt(_cart.global_position.distance_to(start), 1.0, "the cart followed the pusher")
	assert_true(controller.press_use(null), "E again lets go")
	assert_eq(_cart.get_pusher_id(), 0)


func test_cart_cannot_hold_cart() -> void:
	var other := Props.spawn_prop(&"prop_cart_standard", Transform3D(Basis.IDENTITY, Vector3(5, 0.1, 0))) as Cart
	await wait_physics_frames(2)
	assert_false(_cart.can_accept(other))
	assert_false(_cart.add_prop(other))


func test_disallowed_prop_rejected() -> void:
	var weight: NetProp = Props.spawn_prop(&"prop_lift_counterweight", Transform3D(Basis.IDENTITY, Vector3(5, 0.5, 5)))
	await wait_physics_frames(2)
	assert_false(_cart.can_accept(weight), "the counterweight has cart_allowed = false")


func test_contents_follow_into_the_lift_zone() -> void:
	var gem: NetProp = _drop_in(&"prop_gem")
	await wait_until(func() -> bool: return _cart.has_prop(gem), WAIT)
	watch_signals(EventBus)
	_cart.request_take_out(gem)
	assert_signal_emitted(EventBus, "cart_contents_changed")
