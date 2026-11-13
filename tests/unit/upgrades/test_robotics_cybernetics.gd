extends GutTest
## Robotics' cybernetics (NEW 2026-11-12, roadmap WP11, decision D4): Magnet Hand, Spring Legs and Night-Vision Eye.
## Solo: this PC is the host and the player.

const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")
const WAIT: float = 5.0

var _world: Node3D
var _body: PlayerCharacter
var _me: int = 0
var _spawner: EnemySpawner


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
	EventBus.run_ended.emit(&"abandoned")
	await wait_process_frames(2)


func _behaviour(upgrade_id: StringName) -> Node:
	for child: Node in _body.get_children():
		if String(child.name).begins_with("UpgradeBehaviour_%s" % upgrade_id):
			return child
	return null


func test_the_cybernetics_come_from_robotics_data_drives() -> void:
	for id: StringName in [&"cybernetic_magnet_hand", &"cybernetic_spring_legs", &"cybernetic_night_vision_eye"]:
		var data := ContentRegistry.get_content(id) as CyberneticData
		assert_not_null(data, "%s exists" % id)
		assert_eq(data.department_ids, [&"department_robotics"] as Array[StringName], "%s only on Robotics floors" % id)


func test_the_magnet_hand_tugs_gems_towards_you() -> void:
	assert_true(Upgrades.grant(_me, &"cybernetic_magnet_hand"))
	var gem: NetProp = Props.spawn_prop(&"prop_gem", Transform3D(Basis.IDENTITY, Vector3(4, 0.3, 0)))
	var far: NetProp = Props.spawn_prop(&"prop_gem", Transform3D(Basis.IDENTITY, Vector3(12, 0.3, 0)))
	await wait_physics_frames(10)
	var start: float = gem.global_position.distance_to(_body.global_position)
	var far_start: float = far.global_position.distance_to(_body.global_position)
	await wait_seconds(1.0)
	assert_lt(gem.global_position.distance_to(_body.global_position), start - 0.3, "the near gem rolled closer")
	assert_almost_eq(far.global_position.distance_to(_body.global_position), far_start, 0.2, "the far one stayed put")


func test_spring_legs_stomp_on_a_hard_landing() -> void:
	assert_true(Upgrades.grant(_me, &"cybernetic_spring_legs"))
	var rat: Enemy = _spawner.spawn(&"enemy_rat", Transform3D(Basis.IDENTITY, Vector3(1.5, 0.1, 0)), 5.0)
	await wait_physics_frames(3)
	var health: HealthComponent = rat.get_health()
	var before: float = health.get_current()
	_body.landed.emit(3.0)
	assert_eq(health.get_current(), before, "a small hop: no stomp")
	_body.landed.emit(12.0)
	assert_lt(health.get_current(), before, "a hard landing stomps the rat next to you")


func test_night_vision_lights_up_only_your_own_view() -> void:
	assert_true(Upgrades.grant(_me, &"cybernetic_night_vision_eye"))
	await wait_process_frames(2)
	var eye: Node = _behaviour(&"cybernetic_night_vision_eye")
	assert_not_null(eye, "the eye's rule is on your body")
	var light := eye.get("light") as OmniLight3D
	assert_not_null(light, "your own body gets the light")
	assert_true(light.is_inside_tree(), "and it is on")
