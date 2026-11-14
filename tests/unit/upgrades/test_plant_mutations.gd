extends GutTest
## Botany's plant mutations (NEW 2026-11-12, roadmap WP10, decision D4): Photosynthesis, Thorns, Spore Cough and
## Vine Arm, and which department's DNA vials hold them. Solo: this PC is the host and the player.

const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")
const WAIT: float = 8.0
const PLANT_MUTATIONS: Array[StringName] = [&"mutation_photosynthesis", &"mutation_thorns", &"mutation_spore_cough",
	&"mutation_vine_arm"]
const ANIMAL_MUTATIONS: Array[StringName] = [&"mutation_fly", &"mutation_frog", &"mutation_octo", &"mutation_slug",
	&"mutation_giraffe"]

var _world: Node3D
var _body: PlayerCharacter
var _me: int = 0
var _spawner: EnemySpawner


func before_each() -> void:
	EventBus.run_started.emit(1)
	Perception.players_invisible = true
	AttackTickets.clear()
	_me = Net.local_player_id()
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
	var props := PropSpawner.new()
	props.name = "Props"
	_world.add_child(props)
	_spawner = EnemySpawner.new()
	_spawner.name = "TestEnemies"
	_world.add_child(_spawner)
	_body = PLAYER_SCENE.instantiate() as PlayerCharacter
	_body.player_id = _me
	_body.name = str(_me)
	_world.add_child(_body)
	_body.set_input_override(PlayerInputState.new())
	DamageService.give_components(_body, 100.0)
	await wait_physics_frames(3)


func after_each() -> void:
	Perception.players_invisible = false
	Loot.clear_department_override()
	EventBus.run_ended.emit(&"abandoned")
	await wait_process_frames(2)


## The rule node an upgrade adds under the body (named UpgradeBehaviour_<source>, the source being the upgrade id
## and maybe a stack number).
func _behaviour(upgrade_id: StringName) -> Node:
	for child: Node in _body.get_children():
		if String(child.name).begins_with("UpgradeBehaviour_%s" % upgrade_id):
			return child
	return null


func test_botany_vials_hold_plant_mutations_and_zoology_vials_animal_ones() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for id: StringName in PLANT_MUTATIONS:
		assert_eq((ContentRegistry.get_content(id) as UpgradeData).department_ids, [&"department_botany"] as Array[StringName],
			"%s only in Botany" % id)
	Loot.use_department(ContentRegistry.get_content(&"department_botany") as DepartmentData)
	# Other tests register test mutations that may be rolled anywhere, so this checks what must never come up.
	for roll: int in 40:
		assert_does_not_have(ANIMAL_MUTATIONS, Loot.pick_upgrade(&"mutation", rng), "no animal mutations in Botany")
	Loot.use_department(ContentRegistry.get_content(&"department_zoology") as DepartmentData)
	for roll: int in 40:
		assert_does_not_have(PLANT_MUTATIONS, Loot.pick_upgrade(&"mutation", rng), "a Zoology vial holds an animal one")


func test_photosynthesis_heals_you_when_nothing_hurts_you() -> void:
	assert_true(Upgrades.grant(_me, &"mutation_photosynthesis"))
	var health: HealthComponent = HealthComponent.of(_body)
	health.apply_damage(DamageInfo.make(20.0, &"blunt"))
	var hurt: float = health.get_current()
	var calm: float = ((_behaviour(&"mutation_photosynthesis").get_meta(&"params") as Dictionary)["calm_seconds"] as float)
	await wait_seconds(calm * 0.5)
	assert_eq(health.get_current(), hurt, "not yet: you were just hurt")
	await wait_until(func() -> bool: return health.get_current() > hurt + 0.5, calm + 3.0)
	assert_gt(health.get_current(), hurt, "a little later it heals you")


func test_thorns_hurt_whatever_bites_you() -> void:
	assert_true(Upgrades.grant(_me, &"mutation_thorns"))
	var rat: Enemy = _spawner.spawn(&"enemy_rat", Transform3D(Basis.IDENTITY, Vector3(0, 0.1, -1)), 5.0)
	await wait_physics_frames(2)
	var rat_health: HealthComponent = rat.get_health()
	var before: float = rat_health.get_current()
	var bite := DamageInfo.make(5.0, &"sharp", rat)
	Damage.hit(_body, bite)
	assert_lt(rat_health.get_current(), before, "the rat that bit you is pricked back")


func test_spore_cough_makes_close_enemies_sneeze() -> void:
	assert_true(Upgrades.grant(_me, &"mutation_spore_cough"))
	var near: Enemy = _spawner.spawn(&"enemy_rat", Transform3D(Basis.IDENTITY, Vector3(0, 0.1, -2)), 1.0)
	var far: Enemy = _spawner.spawn(&"enemy_rat", Transform3D(Basis.IDENTITY, Vector3(0, 0.1, -12)), 1.0)
	await wait_physics_frames(2)
	var count: int = _behaviour(&"mutation_spore_cough").call("cough")
	assert_eq(count, 1, "one enemy close enough")
	assert_true(StatusEffectComponent.of(near).has_status(&"status_sneezing"), "the near rat sneezes")
	assert_false(StatusEffectComponent.of(far).has_status(&"status_sneezing"), "the far one doesn't")
	assert_almost_eq(near.move_speed(), 0.0, 0.001, "and can't move while it sneezes")


func test_vine_arm_pulls_but_never_punts() -> void:
	assert_true(Upgrades.grant(_me, &"mutation_vine_arm"))
	var arm: PropPunter = PropPunter.of(_body)
	assert_not_null(arm, "the vine is a puller under your body")
	assert_false(arm.can_punt, "it only pulls")
	assert_false(arm.try_punt(), "right click doesn't punt")
