extends GutTest
## Tests for bosses (docs/systems/bosses.md). Solo: this PC is the host. The boss and its minions come
## from the Enemies autoload's spawner, in a test world with a floor and a player.

const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")
const BOSS_ID: StringName = &"boss_giant_rat"
const WAIT: float = 6.0

var _world: Node3D


func before_each() -> void:
	Perception.players_invisible = false
	_world = Node3D.new()
	add_child_autofree(_world)
	_add_box(_world, Vector3(0, -0.5, 0), Vector3(60, 1, 60))


func after_each() -> void:
	Perception.players_invisible = false
	Enemies.despawn_all()
	await wait_process_frames(2)


func _add_box(parent: Node, center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	parent.add_child(body)
	return body


func _player(at: Vector3) -> PlayerCharacter:
	var body := PLAYER_SCENE.instantiate() as PlayerCharacter
	body.player_id = Net.local_player_id()
	body.name = str(body.player_id)
	body.position = at
	_world.add_child(body)
	body.set_input_override(PlayerInputState.new())
	return body


func _boss(at: Vector3 = Vector3(0, 0.2, 0), health_multiplier: float = 1.0) -> Boss:
	return Enemies.get_spawner().spawn(BOSS_ID, Transform3D(Basis.IDENTITY, at), health_multiplier) as Boss


func _hurt_to(boss: Boss, fraction: float) -> void:
	var health: HealthComponent = boss.get_health()
	health.apply_damage(DamageInfo.make(health.get_current() - health.get_max() * fraction, &"blunt"))


func _minions() -> int:
	var count: int = 0
	for enemy: Enemy in Enemies.get_alive():
		if not enemy is Boss:
			count += 1
	return count


func test_attack_found_by_name() -> void:
	var boss := _boss()
	assert_not_null(boss.get_attack(&"charge"))
	assert_not_null(boss.get_attack(&"charge_fast"))
	assert_not_null(boss.get_attack(&"slam"))
	assert_null(boss.get_attack(&"laser_sweep"), "not one of the Giant Rat's")


func test_phase_changes_at_threshold() -> void:
	Perception.players_invisible = true
	var boss := _boss()
	boss.start_fight()
	assert_eq(boss.get_phase(), 0)
	_hurt_to(boss, 0.6)
	assert_eq(boss.get_phase(), 0, "still above half")
	_hurt_to(boss, 0.45)
	assert_eq(boss.get_phase(), 1, "below half: phase 2 (index 1)")


func test_phase_change_emitted_once() -> void:
	Perception.players_invisible = true
	var boss := _boss()
	watch_signals(EventBus)
	boss.start_fight()
	_hurt_to(boss, 0.45)
	_hurt_to(boss, 0.4)
	_hurt_to(boss, 0.3)
	assert_signal_emit_count(EventBus, "boss_phase_changed", 2, "phase 1 at the start, phase 2 once")


func test_minions_spawn_per_wave() -> void:
	Perception.players_invisible = true
	var boss := _boss()
	boss.start_fight()
	assert_eq(_minions(), 0, "phase 1 has no minions")
	_hurt_to(boss, 0.45)
	await wait_process_frames(2)
	assert_eq(_minions(), 3, "phase 2 calls in 3 rats (1 player)")
	boss.spawn_wave()
	await wait_process_frames(2)
	assert_eq(_minions(), 6, "every wave brings more")


func test_health_scales_with_players() -> void:
	var boss := _boss(Vector3(0, 0.2, 0), RunDifficulty.boss_health_multiplier(4))
	assert_eq(boss.get_health().get_max(), 600.0 * RunDifficulty.boss_health_multiplier(4))
	assert_gt(Boss.minions_for_players(3, 4), Boss.minions_for_players(3, 1), "and more minions")
	assert_eq(Boss.minions_for_players(3, 1), 3)


func test_defeat_emits_boss_defeated() -> void:
	Perception.players_invisible = true
	var boss := _boss()
	boss.start_fight()
	_hurt_to(boss, 0.45)
	await wait_process_frames(2)
	watch_signals(EventBus)
	boss.get_health().apply_damage(DamageInfo.make(99999.0, &"blunt"))
	assert_signal_emitted_with_parameters(EventBus, "boss_defeated", [BOSS_ID])
	await wait_process_frames(3)
	assert_eq(_minions(), 0, "its minions go with it")


func test_boss_attacks_close_players() -> void:
	var player := _player(Vector3(0, 0, -3.5))
	_boss()
	await wait_until(func() -> bool: return HealthComponent.of(player).get_current() < Config.game.player_max_health, WAIT)
	assert_lt(HealthComponent.of(player).get_current(), Config.game.player_max_health, "it slams or charges you")


func test_doors_lock_and_unlock() -> void:
	var room := Node3D.new()
	room.name = "ArenaRoom"
	_world.add_child(room)
	var doorway := RoomDoorway.new()
	doorway.name = "DoorNorth"
	doorway.position = Vector3(12, 0, 0)
	room.add_child(doorway)
	var arena := BossArena.new()
	arena.setup(room, Vector2(24, 24))
	room.add_child(arena)
	Perception.players_invisible = true
	var boss := _boss(Vector3(12, 0.2, 18))
	assert_false(arena.is_locked())
	_player(Vector3(12, 0.1, 6))
	await wait_until(func() -> bool: return arena.is_locked(), WAIT)
	assert_true(arena.is_locked(), "everyone is inside: the doors lock")
	assert_true(boss.is_fighting(), "and the fight is on")
	var bars := arena.get_node("Bars_DoorNorth") as StaticBody3D
	assert_true(bars.visible)
	assert_eq(bars.collision_layer, PhysicsLayers.bit(PhysicsLayers.WORLD), "the bars are solid")
	boss.get_health().apply_damage(DamageInfo.make(99999.0, &"blunt"))
	assert_false(arena.is_locked(), "boss beaten: the doors open")
	assert_false(bars.visible)


func test_department_boss_or_the_first_one() -> void:
	assert_eq(BossesService.boss_for(null), BOSS_ID, "no department yet: the Giant Rat")
	var department := DepartmentData.new()
	department.boss_id = BOSS_ID
	assert_eq(BossesService.boss_for(department), BOSS_ID)
