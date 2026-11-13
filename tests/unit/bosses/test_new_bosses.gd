extends GutTest
## The Mushroom Man (Botany) and Robobrain (Robotics), and the attack pieces they brought: projectile burst, laser
## sweep and the slam's status (NEW 2026-11-12, roadmap WP13). Solo: this PC is the host.

const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")
const MUSHROOM_MAN: StringName = &"boss_mushroom_man"
const ROBOBRAIN: StringName = &"boss_robobrain"
const WAIT: float = 8.0

var _world: Node3D


func before_each() -> void:
	# Bosses stand still until a test starts an attack by hand.
	Perception.players_invisible = true
	_world = Node3D.new()
	add_child_autofree(_world)
	_add_box(Vector3(0, -0.5, 0), Vector3(80, 1, 80))


func after_each() -> void:
	Perception.players_invisible = false
	Enemies.despawn_all()
	for shot: EnemyProjectile in Enemies.get_projectiles():
		shot.queue_free()
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


func _player(at: Vector3) -> PlayerCharacter:
	var body := PLAYER_SCENE.instantiate() as PlayerCharacter
	body.player_id = Net.local_player_id()
	body.name = str(body.player_id)
	body.position = at
	_world.add_child(body)
	body.set_input_override(PlayerInputState.new())
	DamageService.give_components(body, 100.0)
	return body


func _boss(boss_id: StringName, at: Vector3 = Vector3(0, 0.2, 0)) -> Boss:
	return Enemies.get_spawner().spawn(boss_id, Transform3D(Basis.IDENTITY, at), 1.0) as Boss


func _minions() -> Array[Enemy]:
	var found: Array[Enemy] = []
	for enemy: Enemy in Enemies.get_alive():
		if not enemy is Boss:
			found.append(enemy)
	return found


## Runs one attack by hand, a physics frame at a time, until it says it is finished.
func _run_attack(boss: Boss, attack: BossAttack, target: PlayerCharacter) -> void:
	attack.start(boss, target)
	attack.play_effect(boss)
	var frames: int = 0
	while not attack.is_finished() and frames < 900:
		attack.update(boss, get_physics_process_delta_time())
		await wait_physics_frames(1)
		frames += 1
	assert_true(attack.is_finished(), "%s ends by itself" % attack.attack_name)


func test_every_department_has_its_own_boss() -> void:
	var expected: Dictionary[StringName, StringName] = {
		&"department_zoology": &"boss_giant_rat",
		&"department_botany": MUSHROOM_MAN,
		&"department_robotics": ROBOBRAIN,
	}
	for department_id: StringName in expected:
		var department := ContentRegistry.get_content(department_id) as DepartmentData
		assert_eq(department.boss_id, expected[department_id], "%s has its own boss" % department_id)
		assert_true(department.boss_floors, "%s has boss floors" % department_id)
		assert_eq(BossesService.boss_for(department), expected[department_id])


func test_every_boss_phase_only_names_attacks_and_minions_that_exist() -> void:
	for content: ContentData in ContentRegistry.get_all(&"boss"):
		var data := content as BossData
		var boss: Boss = _boss(data.id)
		assert_not_null(boss, "%s spawns" % data.id)
		assert_gt(data.phases.size(), 0, "%s has phases" % data.id)
		assert_true(ContentRegistry.get_content(data.loot_id) is LootTableData, "%s has a loot table" % data.id)
		for phase: BossPhaseData in data.phases:
			assert_gt(phase.attack_names.size(), 0, "%s: every phase has an attack" % data.id)
			for attack_name: String in phase.attack_names:
				assert_not_null(boss.get_attack(StringName(attack_name)), "%s has the attack '%s'" % [data.id, attack_name])
			for minion_id: StringName in phase.minion_enemy_ids:
				assert_true(ContentRegistry.get_content(minion_id) is EnemyData, "%s: minion %s exists" % [data.id, minion_id])
		Enemies.despawn_all()
		await wait_process_frames(2)


func test_all_three_departments_turn_up_as_boss_floors() -> void:
	var seen: Dictionary[StringName, bool] = {}
	var every: int = maxi(Config.game.boss_every_floors, 1)
	for run_seed: int in 40:
		var floors: Array[StringName] = GameFlow.floor_departments(run_seed)
		for floor_number: int in range(every, floors.size() + 1, every):
			seen[floors[floor_number - 1]] = true
	for department_id: StringName in [&"department_zoology", &"department_botany", &"department_robotics"]:
		assert_true(seen.has(department_id), "%s gets boss floors" % department_id)


func test_the_mushroom_man_wakes_zombies_when_the_fight_starts() -> void:
	var boss: Boss = _boss(MUSHROOM_MAN)
	boss.start_fight()
	await wait_process_frames(2)
	var minions: Array[Enemy] = _minions()
	assert_eq(minions.size(), 2, "2 mushroom zombies for 1 player")
	for minion: Enemy in minions:
		assert_eq(minion.data.id, &"enemy_mushroom_zombie")


func test_the_mushroom_man_has_three_phases() -> void:
	var boss: Boss = _boss(MUSHROOM_MAN)
	boss.start_fight()
	var health: HealthComponent = boss.get_health()
	assert_eq(boss.get_phase(), 0)
	health.apply_damage(DamageInfo.make(health.get_max() * 0.45, &"blunt"))
	assert_eq(boss.get_phase(), 1, "under 60%: the spore ring phase")
	health.apply_damage(DamageInfo.make(health.get_max() * 0.35, &"blunt"))
	assert_eq(boss.get_phase(), 2, "under 25%: the last phase")


func test_the_spore_volley_is_a_fan_of_lobbed_spores() -> void:
	var player := _player(Vector3(0, 0, -10))
	var boss: Boss = _boss(MUSHROOM_MAN)
	await wait_physics_frames(2)
	var volley: BossAttack = boss.get_attack(&"spore_volley")
	volley.start(boss, player)
	var frames: int = 0
	while Enemies.get_projectiles().is_empty() and frames < 300:
		volley.update(boss, get_physics_process_delta_time())
		await wait_physics_frames(1)
		frames += 1
	var shots: Array[EnemyProjectile] = Enemies.get_projectiles()
	assert_eq(shots.size(), 5, "5 spores in the first volley")
	var left: int = 0
	var right: int = 0
	for shot: EnemyProjectile in shots:
		assert_lt(shot.velocity.z, 0.0, "every spore flies towards you")
		assert_gt(shot.velocity.y, 0.0, "and is lobbed upwards")
		assert_eq(shot.attack.status_id, &"status_spores")
		if shot.velocity.x < -0.5:
			left += 1
		elif shot.velocity.x > 0.5:
			right += 1
	assert_gt(left, 0, "some go left of you")
	assert_gt(right, 0, "and some go right")


func test_the_spore_ring_goes_out_in_every_direction() -> void:
	var player := _player(Vector3(0, 0, -6))
	var boss: Boss = _boss(MUSHROOM_MAN)
	await wait_physics_frames(2)
	var ring: BossAttack = boss.get_attack(&"spore_ring")
	ring.start(boss, player)
	var frames: int = 0
	while Enemies.get_projectiles().is_empty() and frames < 300:
		ring.update(boss, get_physics_process_delta_time())
		await wait_physics_frames(1)
		frames += 1
	var shots: Array[EnemyProjectile] = Enemies.get_projectiles()
	assert_eq(shots.size(), 14, "14 spores in a ring")
	var behind: int = 0
	for shot: EnemyProjectile in shots:
		if shot.velocity.z > 0.5:
			behind += 1
	assert_gt(behind, 3, "some fly away from you: it is a whole ring")


func test_a_boss_spore_hurts_and_makes_you_cough() -> void:
	var player := _player(Vector3(0, 0, -7))
	var boss: Boss = _boss(MUSHROOM_MAN)
	await wait_physics_frames(2)
	var health: HealthComponent = HealthComponent.of(player)
	var statuses: StatusEffectComponent = StatusEffectComponent.of(player)
	var volley: BossAttack = boss.get_attack(&"spore_volley")
	# One spore, fired straight at your chest from 3 m (the fan's own aim has a little random spread).
	boss.fire_attack_projectile(volley, Vector3(0, 1.2, -4), Vector3(0, 0, -volley.get_projectile().projectile_speed))
	await wait_until(func() -> bool: return health.get_current() < 100.0, WAIT)
	assert_lt(health.get_current(), 100.0, "the spore lands on you")
	assert_true(statuses.has_status(&"status_spores"), "and you cough spores")
	assert_eq(Enemies.get_projectiles().size(), 0, "the spore is gone")


func test_the_spore_slam_gives_everyone_close_spores() -> void:
	var player := _player(Vector3(0, 0, -3))
	var boss: Boss = _boss(MUSHROOM_MAN)
	await wait_physics_frames(2)
	await _run_attack(boss, boss.get_attack(&"spore_slam"), player)
	assert_lt(HealthComponent.of(player).get_current(), 100.0, "the slam hurts")
	assert_true(StatusEffectComponent.of(player).has_status(&"status_spores"), "and leaves you coughing")


func test_the_laser_beam_can_be_jumped_and_has_an_end() -> void:
	var boss: Boss = _boss(ROBOBRAIN)
	var laser: BossAttack = boss.get_attack(&"laser_sweep")
	var origin := Vector3.ZERO
	var forward := Vector3.FORWARD
	assert_true(laser.call("beam_touches", origin, forward, Vector3(0, 0, -8)), "standing in the beam")
	assert_true(laser.call("beam_touches", origin, forward, Vector3(0.5, 0, -8)), "its edge still catches you")
	assert_false(laser.call("beam_touches", origin, forward, Vector3(0, 0.7, -8)), "feet above it (a jump): missed")
	assert_false(laser.call("beam_touches", origin, forward, Vector3(2.0, 0, -8)), "beside it: missed")
	assert_false(laser.call("beam_touches", origin, forward, Vector3(0, 0, 8)), "behind the boss: missed")
	assert_false(laser.call("beam_touches", origin, forward, Vector3(0, 0, -40)), "past its end: missed")
	var player := _player(Vector3(0, 0, 12))
	assert_lt(float(laser.get("beam_height")), player.tuning.jump_height * 0.7, "the beam is well under a jump's height")


func test_the_laser_sweep_hits_you_once_and_turns_the_boss() -> void:
	var player := _player(Vector3(0, 0, -7))
	var boss: Boss = _boss(ROBOBRAIN)
	await wait_physics_frames(2)
	var laser: BossAttack = boss.get_attack(&"laser_sweep")
	var start_yaw: float = boss.rotation.y
	var widest: float = 0.0
	laser.start(boss, null)
	laser.play_effect(boss)
	assert_not_null(boss.get_node_or_null(^"LaserBeam"), "everyone sees the aiming line")
	var frames: int = 0
	while not laser.is_finished() and frames < 900:
		laser.update(boss, get_physics_process_delta_time())
		widest = maxf(widest, absf(angle_difference(start_yaw, boss.rotation.y)))
		await wait_physics_frames(1)
		frames += 1
	assert_true(laser.is_finished())
	assert_gt(rad_to_deg(widest), 50.0, "the boss turned through the arc")
	assert_almost_eq(HealthComponent.of(player).get_current(), 100.0 - float(laser.get("damage")), 0.01,
		"the beam passed over you and hit exactly once")


func test_standing_on_something_dodges_the_laser() -> void:
	_add_box(Vector3(0, 0.5, -7), Vector3(2, 1, 2))
	var player := _player(Vector3(0, 1.05, -7))
	var boss: Boss = _boss(ROBOBRAIN)
	await wait_physics_frames(10)
	await _run_attack(boss, boss.get_attack(&"laser_sweep"), null)
	assert_eq(HealthComponent.of(player).get_current(), 100.0, "up on a crate: the beam passes under you")


func test_the_rocket_volley_fires_straight_pairs() -> void:
	var player := _player(Vector3(0, 0, -12))
	var boss: Boss = _boss(ROBOBRAIN)
	await wait_physics_frames(2)
	var rockets: BossAttack = boss.get_attack(&"rocket_volley")
	rockets.start(boss, player)
	var frames: int = 0
	while Enemies.get_projectiles().is_empty() and frames < 300:
		rockets.update(boss, get_physics_process_delta_time())
		await wait_physics_frames(1)
		frames += 1
	var shots: Array[EnemyProjectile] = Enemies.get_projectiles()
	assert_eq(shots.size(), 2, "one rocket from each arm")
	for shot: EnemyProjectile in shots:
		assert_eq(shot.attack.gravity_scale, 0.0, "rockets fly straight")
		assert_lt(shot.velocity.z, -8.0, "towards you")


func test_robobrain_calls_drones_in_its_second_phase() -> void:
	var boss: Boss = _boss(ROBOBRAIN)
	boss.start_fight()
	await wait_process_frames(2)
	assert_eq(_minions().size(), 0, "no drones at first")
	var health: HealthComponent = boss.get_health()
	health.apply_damage(DamageInfo.make(health.get_max() * 0.45, &"blunt"))
	await wait_process_frames(2)
	var minions: Array[Enemy] = _minions()
	assert_eq(minions.size(), 2, "2 drones for 1 player")
	for minion: Enemy in minions:
		assert_eq(minion.data.id, &"enemy_drone")


func test_beating_each_new_boss_ends_the_fight() -> void:
	for boss_id: StringName in [MUSHROOM_MAN, ROBOBRAIN]:
		var boss: Boss = _boss(boss_id)
		boss.start_fight()
		await wait_process_frames(2)
		watch_signals(EventBus)
		boss.get_health().apply_damage(DamageInfo.make(99999.0, &"blunt"))
		assert_signal_emitted_with_parameters(EventBus, "boss_defeated", [boss_id])
		await wait_process_frames(3)
		assert_eq(_minions().size(), 0, "%s's minions go with it" % boss_id)
		Enemies.despawn_all()
		await wait_process_frames(2)
