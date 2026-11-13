extends GutTest
## Lures (NEW 2026-11-12, roadmap WP14): things certain enemies can't resist. The laser pointer's dot (rats, bats,
## roombas), trash (flies, roombas) and Fly players (flies). Solo: this PC is the host.

const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")
const WAIT: float = 6.0
const PRIMARY: int = ItemBehaviourData.Trigger.PRIMARY

var _world: Node3D
var _saved: Dictionary[String, float] = {}


func before_each() -> void:
	Perception.players_invisible = false
	_world = Node3D.new()
	add_child_autofree(_world)
	_add_box(Vector3(0, -0.5, 0), Vector3(80, 1, 80))
	var props := PropSpawner.new()
	props.name = "Props"
	_world.add_child(props)
	for field: String in ["lure_attention_seconds", "lure_bored_seconds", "lure_check_seconds"]:
		_saved[field] = float(Config.feel.ai.get(field))


func after_each() -> void:
	for field: String in _saved:
		Config.feel.ai.set(field, _saved[field])
	Perception.players_invisible = false
	Enemies.despawn_all()
	for lure: Lure in Enemies.get_lures():
		lure.queue_free()
	await wait_process_frames(2)


func _add_box(center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	_world.add_child(body)
	return body


func _player(at: Vector3, player_id: int = 0) -> PlayerCharacter:
	var body := PLAYER_SCENE.instantiate() as PlayerCharacter
	body.player_id = player_id if player_id != 0 else Net.local_player_id()
	body.name = str(body.player_id)
	body.position = at
	_world.add_child(body)
	body.set_input_override(PlayerInputState.new())
	DamageService.give_components(body, 100.0)
	return body


func _spawn(enemy_id: StringName, at: Vector3) -> Enemy:
	return Enemies.get_spawner().spawn(enemy_id, Transform3D(Basis.IDENTITY, at), 1.0)


func _state_is(enemy: Enemy, state: StringName) -> Callable:
	return func() -> bool: return enemy.get_state() == state


func test_which_enemies_fall_for_what() -> void:
	var expected: Dictionary[StringName, Array] = {
		&"enemy_rat": ["laser"], &"enemy_bat": ["laser"], &"enemy_roomba": ["laser", "trash"],
		&"enemy_fly": ["trash", "fly_player"], &"enemy_kangaroo": [], &"enemy_mushroom_zombie": [],
	}
	for enemy_id: StringName in expected:
		var data := ContentRegistry.get_content(enemy_id) as EnemyData
		assert_eq(Array(data.lure_kinds), expected[enemy_id], "%s" % enemy_id)
	var rat: Enemy = _spawn(&"enemy_rat", Vector3(0, 0.1, 0))
	var kangaroo: Enemy = _spawn(&"enemy_kangaroo", Vector3(5, 0.1, 0))
	assert_true(rat.has_state(&"lured"), "an enemy with lure_kinds gets the lured state by itself")
	assert_false(kangaroo.has_state(&"lured"), "one without doesn't")


func test_a_rat_chasing_you_goes_for_the_laser_dot_instead() -> void:
	var player := _player(Vector3(0, 0, -6))
	var rat: Enemy = _spawn(&"enemy_rat", Vector3(0, 0.1, 0))
	await wait_until(func() -> bool: return rat.get_target() == player, WAIT)
	assert_eq(rat.get_target(), player, "first it is after you")
	Enemies.place_lure("laser_test", &"laser", Vector3(7, 0.1, 0), 12.0, 30.0, Color.RED)
	await wait_until(_state_is(rat, &"lured"), WAIT)
	assert_eq(rat.get_state(), &"lured", "then it sees the dot")
	assert_null(rat.get_target(), "and forgets you")
	await wait_until(func() -> bool: return rat.global_position.distance_to(Vector3(7, 0.1, 0)) < 1.6, WAIT)
	assert_lt(rat.global_position.distance_to(Vector3(7, 0.1, 0)), 1.6, "it runs to the dot")
	assert_eq(HealthComponent.of(player).get_current(), 100.0, "and you weren't bitten on the way")


func test_everyone_sees_one_dot_per_key_and_it_goes_out() -> void:
	Enemies.place_lure("laser_1", &"laser", Vector3(1, 0.1, 0), 12.0, 0.4, Color.RED)
	Enemies.place_lure("laser_1", &"laser", Vector3(3, 0.1, 0), 12.0, 0.4, Color.RED)
	Enemies.place_lure("laser_2", &"laser", Vector3(-3, 0.1, 0), 12.0, 0.4, Color.RED)
	var lures: Array[Lure] = Enemies.get_lures(&"laser")
	assert_eq(lures.size(), 2, "placing again with the same key moves the dot")
	assert_almost_eq(lures[0].global_position.x, 3.0, 0.01)
	assert_not_null(lures[0].get_node_or_null(^"Dot"), "the dot is something you can see")
	await wait_seconds(0.7)
	assert_eq(Enemies.get_lures(&"laser").size(), 0, "dots go out by themselves")


func test_a_kangaroo_ignores_the_laser() -> void:
	Perception.players_invisible = true
	var kangaroo: Enemy = _spawn(&"enemy_kangaroo", Vector3(0, 0.1, 0))
	Enemies.place_lure("laser_test", &"laser", Vector3(4, 0.1, 0), 12.0, 30.0, Color.RED)
	await wait_seconds(1.0)
	assert_ne(kangaroo.get_state(), &"lured")


func test_a_wall_hides_the_dot() -> void:
	Perception.players_invisible = true
	_add_box(Vector3(3, 1.5, 0), Vector3(0.3, 3, 12))
	var rat: Enemy = _spawn(&"enemy_rat", Vector3(0, 0.1, 0))
	Enemies.place_lure("laser_test", &"laser", Vector3(7, 0.1, 0), 12.0, 30.0, Color.RED)
	await wait_seconds(1.0)
	assert_ne(rat.get_state(), &"lured", "it can't see a dot behind a wall")
	# A dot ON the wall it faces is seen (the dot sits a little off the surface).
	Enemies.place_lure("laser_test", &"laser", Vector3(2.77, 0.4, 0), 12.0, 30.0, Color.RED)
	await wait_until(_state_is(rat, &"lured"), WAIT)
	assert_eq(rat.get_state(), &"lured")


func test_it_gets_bored_and_then_ignores_lures_for_a_while() -> void:
	Perception.players_invisible = true
	Config.feel.ai.lure_attention_seconds = 0.6
	Config.feel.ai.lure_bored_seconds = 30.0
	var rat: Enemy = _spawn(&"enemy_rat", Vector3(0, 0.1, 0))
	Enemies.place_lure("laser_test", &"laser", Vector3(2, 0.1, 0), 12.0, 60.0, Color.RED)
	await wait_until(_state_is(rat, &"lured"), WAIT)
	assert_eq(rat.get_state(), &"lured")
	await wait_until(func() -> bool: return rat.get_state() != &"lured", WAIT)
	assert_ne(rat.get_state(), &"lured", "it loses interest")
	await wait_seconds(1.0)
	assert_ne(rat.get_state(), &"lured", "and the dot doesn't catch it again straight away")


func test_hurting_it_snaps_it_out() -> void:
	var player := _player(Vector3(0, 0, -30))
	Perception.players_invisible = true
	var rat: Enemy = _spawn(&"enemy_rat", Vector3(0, 0.1, 0))
	Enemies.place_lure("laser_test", &"laser", Vector3(3, 0.1, 0), 12.0, 60.0, Color.RED)
	await wait_until(_state_is(rat, &"lured"), WAIT)
	Perception.players_invisible = false
	rat.on_hurt_by(player)
	assert_ne(rat.get_state(), &"lured", "pain beats the dot")
	assert_eq(rat.get_target(), player, "and it comes for whoever hurt it")
	await wait_seconds(1.0)
	assert_ne(rat.get_state(), &"lured", "the dot doesn't take it back straight away")


func test_the_laser_pointer_puts_a_dot_where_you_point() -> void:
	Perception.players_invisible = true
	var player := _player(Vector3.ZERO)
	_add_box(Vector3(0, 1.5, -8), Vector3(10, 3, 0.3))
	await wait_physics_frames(3)
	var data := ContentRegistry.get_content(&"item_laser_pointer") as ItemData
	assert_not_null(data, "the laser pointer exists")
	var inventory: InventoryComponent = InventoryComponent.of(player)
	assert_true(inventory.add_item(&"item_laser_pointer", data.uses))
	inventory.request_select(inventory.find_item(&"item_laser_pointer"))
	ItemsService.held_of(player).use(PRIMARY)
	await wait_until(func() -> bool: return not Enemies.get_lures(&"laser").is_empty(), WAIT)
	var lures: Array[Lure] = Enemies.get_lures(&"laser")
	assert_eq(lures.size(), 1, "one dot")
	assert_almost_eq(lures[0].global_position.z, -7.85, 0.15, "on the wall you pointed at, just off its surface")
	assert_true(inventory.find_item(&"item_laser_pointer") >= 0, "the pointer isn't used up")
	for stock_id: StringName in [&"stock_zoology_vending", &"stock_robotics_vending"]:
		var stock := ContentRegistry.get_content(stock_id) as VendorStockData
		var sold: bool = false
		for entry: Resource in stock.entries:
			sold = sold or entry.get("item_id") == &"item_laser_pointer"
		assert_true(sold, "%s sells it" % stock_id)


func test_trash_draws_flies_and_roombas_and_follows_the_bag() -> void:
	Perception.players_invisible = true
	Config.feel.ai.lure_attention_seconds = 60.0
	var bag: NetProp = Props.spawn_prop(&"prop_trash_bag", Transform3D(Basis.IDENTITY, Vector3(5, 0.4, 0)))
	assert_not_null(bag, "the trash bag exists")
	var fly: Enemy = _spawn(&"enemy_fly", Vector3(0, 0.1, 0))
	var roomba: Enemy = _spawn(&"enemy_roomba", Vector3(0, 0.1, 3))
	var rat: Enemy = _spawn(&"enemy_rat", Vector3(0, 0.1, -3))
	await wait_until(func() -> bool: return Enemies.get_lures(&"trash").size() == 1, WAIT)
	assert_eq(Enemies.get_lures(&"trash").size(), 1, "the host puts a lure on the bag")
	await wait_until(func() -> bool: return fly.get_state() == &"lured" and roomba.get_state() == &"lured", WAIT)
	assert_eq(fly.get_state(), &"lured", "flies love trash")
	assert_eq(roomba.get_state(), &"lured", "so do robot vacuums")
	assert_ne(rat.get_state(), &"lured", "rats don't care")
	Props.despawn(bag)
	await wait_until(func() -> bool: return Enemies.get_lures(&"trash").is_empty(), WAIT)
	assert_eq(Enemies.get_lures(&"trash").size(), 0, "no bag, no lure")
	await wait_until(func() -> bool: return fly.get_state() != &"lured", WAIT)
	assert_ne(fly.get_state(), &"lured", "and the fly goes back to its business")


func test_flies_smell_a_fly_player_through_a_wall() -> void:
	# A wall between you and the fly: it can't see you, so it leaves you alone.
	_add_box(Vector3(0, 1.5, 4), Vector3(14, 3, 0.3))
	var player := _player(Vector3(0, 0, 8))
	var fly: Enemy = _spawn(&"enemy_fly", Vector3(0, 0.1, 0))
	await wait_seconds(1.5)
	assert_null(fly.get_target(), "out of sight: the fly hasn't noticed you")
	# The Fly mutation puts a "fly_player" lure on you: flies notice you from afar, seen or not.
	var lure: Lure = Enemies.attach_lure(player, &"fly_player", 14.0)
	assert_eq(lure.player, player)
	await wait_until(func() -> bool: return fly.get_target() == player, WAIT)
	assert_eq(fly.get_target(), player, "now it comes for you")
	assert_ne(fly.get_state(), &"lured", "it attacks; it doesn't just stare")
	var rat: Enemy = _spawn(&"enemy_rat", Vector3(3, 0.1, 0))
	await wait_seconds(1.0)
	assert_null(rat.get_target(), "a rat doesn't care that you are a Fly")
