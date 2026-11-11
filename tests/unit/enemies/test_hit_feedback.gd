extends GutTest
## Hit feedback (NEW 2026-11-11, roadmap WP7): a hit enemy flashes and flinches, a dead one pops into a puff of cubes,
## and Effects' bursts and floating text clean themselves up. Solo: this PC is the host.

const WAIT: float = 3.0

var _world: Node3D
var _spawner: EnemySpawner


func before_each() -> void:
	Perception.players_invisible = true
	_world = Node3D.new()
	add_child_autofree(_world)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	_world.add_child(floor_body)
	_spawner = EnemySpawner.new()
	_spawner.name = "TestEnemies"
	_world.add_child(_spawner)


func after_each() -> void:
	Perception.players_invisible = false


func _bursts(parent: Node) -> int:
	return parent.find_children("Burst", "CPUParticles3D", false, false).size()


func test_a_hit_enemy_flashes_and_flinches_then_settles() -> void:
	var rat: Enemy = _spawner.spawn(&"enemy_rat", Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0)), 3.0)
	await wait_physics_frames(2)
	var mesh := rat.get_node(^"Mesh") as GeometryInstance3D
	var rest: Vector3 = mesh.position
	assert_false(rat.is_reacting_to_hit(), "calm before the hit")
	rat.get_health().apply_damage(DamageInfo.make(1.0, &"blunt"))
	assert_true(rat.is_reacting_to_hit(), "it reacts to the hit")
	assert_not_null(mesh.material_overlay, "it flashes white")
	await wait_until(func() -> bool: return not rat.is_reacting_to_hit(), WAIT)
	assert_null(mesh.material_overlay, "the flash is over")
	assert_almost_eq(mesh.position, rest, Vector3.ONE * 0.001, "and its body is back in place")


func test_a_dead_enemy_pops_into_cubes() -> void:
	var rat: Enemy = _spawner.spawn(&"enemy_rat", Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0)), 1.0)
	await wait_physics_frames(2)
	var before: int = _bursts(rat.get_parent())
	rat.get_health().apply_damage(DamageInfo.make(1000.0, &"blunt"))
	assert_eq(_bursts(rat.get_parent()), before + 1, "a puff of cubes where it died")


func test_effects_clean_themselves_up() -> void:
	var burst: CPUParticles3D = Effects.burst(_world, Vector3.ZERO, Color.WHITE, 8, 2.0, 0.05, 0.2)
	var text: Label3D = Effects.float_text(_world, Vector3.ZERO, "+5", Color.YELLOW, 0.5, 0.2)
	assert_not_null(burst)
	assert_eq(text.text, "+5")
	await wait_seconds(0.6)
	assert_false(is_instance_valid(burst), "the burst is gone")
	assert_false(is_instance_valid(text), "the text is gone")
