extends GutTest
## The Fly mutation's instincts (NEW 2026-11-12, roadmap WP14): enemy flies are drawn to you, and you heal near
## trash. Also: the Giraffe has to crouch through doorways. Solo: this PC is the host and the player.

const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")
const WAIT: float = 5.0

var _world: Node3D
var _body: PlayerCharacter
var _me: int = 0


func before_each() -> void:
	EventBus.run_started.emit(1)
	Perception.players_invisible = true
	_me = Net.local_player_id()
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
	_body.player_id = _me
	_body.name = str(_me)
	_world.add_child(_body)
	_body.set_input_override(PlayerInputState.new())
	DamageService.give_components(_body, 100.0)
	await wait_physics_frames(3)


func after_each() -> void:
	Perception.players_invisible = false
	EventBus.run_ended.emit(&"abandoned")
	for lure: Lure in Enemies.get_lures():
		lure.queue_free()
	await wait_process_frames(2)


func _fly_lures() -> Array[Lure]:
	return Enemies.get_lures(&"fly_player")


func test_a_fly_player_carries_a_lure_for_flies() -> void:
	assert_eq(_fly_lures().size(), 0)
	assert_true(Upgrades.grant(_me, &"mutation_fly"))
	await wait_until(func() -> bool: return _fly_lures().size() == 1, WAIT)
	assert_eq(_fly_lures().size(), 1, "the Fly mutation makes you smell like one")
	assert_eq(_fly_lures()[0].player, _body, "the lure is you")
	assert_false(_fly_lures()[0].needs_sight, "flies find you whether they see you or not")


func test_a_fly_player_heals_near_trash_only() -> void:
	assert_true(Upgrades.grant(_me, &"mutation_fly"))
	var health: HealthComponent = HealthComponent.of(_body)
	health.apply_damage(DamageInfo.make(50.0, &"blunt"))
	var hurt: float = health.get_current()
	await wait_seconds(0.8)
	assert_almost_eq(health.get_current(), hurt, 0.01, "no trash about: no healing")
	Props.spawn_prop(&"prop_trash_bag", Transform3D(Basis.IDENTITY, Vector3(2, 0.4, 0)))
	await wait_until(func() -> bool: return health.get_current() > hurt + 0.5, WAIT)
	assert_gt(health.get_current(), hurt + 0.5, "next to a trash bag you feel better")


func test_someone_without_the_mutation_gets_nothing_from_trash() -> void:
	var health: HealthComponent = HealthComponent.of(_body)
	health.apply_damage(DamageInfo.make(50.0, &"blunt"))
	var hurt: float = health.get_current()
	Props.spawn_prop(&"prop_trash_bag", Transform3D(Basis.IDENTITY, Vector3(2, 0.4, 0)))
	await wait_seconds(1.5)
	assert_almost_eq(health.get_current(), hurt, 0.01)
	assert_eq(_fly_lures().size(), 0)


## A lintel across the way at doorway height: the wall above a door, from the top of the doorway up.
func _doorway_top(z: float) -> void:
	var lintel := StaticBody3D.new()
	lintel.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 2.0, 0.3)
	shape.shape = box
	lintel.add_child(shape)
	lintel.position = Vector3(0, Config.floor_gen.doorway_height + 1.0, z)
	_world.add_child(lintel)


func test_the_giraffe_has_to_crouch_through_a_doorway() -> void:
	_doorway_top(-3.0)
	assert_true(Upgrades.grant(_me, &"mutation_giraffe"))
	await wait_physics_frames(10)
	assert_gt(_body.get_movement().get_height(), Config.floor_gen.doorway_height, "a Giraffe is taller than a doorway")
	var walk := PlayerInputState.new()
	walk.move = Vector2(0, 1)
	_body.set_input_override(walk)
	await wait_seconds(2.0)
	assert_gt(_body.global_position.z, -3.0, "standing tall, the top of the doorway stops you")
	var duck := PlayerInputState.new()
	duck.move = Vector2(0, 1)
	duck.crouch = true
	_body.set_input_override(duck)
	await wait_until(func() -> bool: return _body.global_position.z < -4.0, WAIT)
	assert_lt(_body.global_position.z, -4.0, "crouched, you fit through")


func test_someone_of_normal_height_walks_straight_through() -> void:
	_doorway_top(-3.0)
	var walk := PlayerInputState.new()
	walk.move = Vector2(0, 1)
	_body.set_input_override(walk)
	await wait_until(func() -> bool: return _body.global_position.z < -4.0, WAIT)
	assert_lt(_body.global_position.z, -4.0)
