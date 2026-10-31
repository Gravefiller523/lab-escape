extends GutTest
## Tests for hazards (docs/systems/hazards.md): placeholder zones that hurt through the damage system.


func _victim(parent: Node, at: Vector3) -> CharacterBody3D:
	var victim := CharacterBody3D.new()
	victim.collision_layer = PhysicsLayers.bit(PhysicsLayers.PLAYERS)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 1.8, 0.6)
	shape.shape = box
	shape.position.y = 0.9
	victim.add_child(shape)
	parent.add_child(victim)
	victim.global_position = at
	DamageService.give_components(victim, 100.0, 0.0)
	return victim


func _world() -> Node3D:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_child_autofree(viewport)
	var root := Node3D.new()
	viewport.add_child(root)
	return root


func test_a_fire_hurts_whoever_stands_in_it() -> void:
	var root: Node3D = _world()
	var zone := HazardZone.new()
	zone.setup(&"fire")
	root.add_child(zone)
	var inside: CharacterBody3D = _victim(root, Vector3(0.3, 0, 0))
	var outside: CharacterBody3D = _victim(root, Vector3(6, 0, 0))
	await wait_seconds(Config.floor_gen.hazard_tick_seconds * 2.5)
	assert_lt(HealthComponent.of(inside).get_current(), 100.0, "standing in the fire hurts")
	assert_eq(HealthComponent.of(outside).get_current(), 100.0, "standing away from it doesn't")


func test_sparks_use_the_tuning_numbers() -> void:
	var root: Node3D = _world()
	var zone := HazardZone.new()
	zone.setup(&"sparks")
	root.add_child(zone)
	var victim: CharacterBody3D = _victim(root, Vector3.ZERO)
	var tuning: FloorGenTuning = Config.floor_gen
	await wait_seconds(tuning.hazard_tick_seconds * 1.5)
	var lost: float = 100.0 - HealthComponent.of(victim).get_current()
	assert_almost_eq(lost, tuning.hazard_damage_per_second[&"sparks"] * tuning.hazard_tick_seconds, 0.01,
		"one tick of sparks damage")


func test_hazards_appear_at_the_markers_the_plan_switched_on() -> void:
	var robotics := ContentRegistry.get_content(&"department_robotics") as DepartmentData
	FloorGenerator.debug_damage = &"destroyed"
	var layout: FloorLayout = FloorGenerator.generate_from_seed(robotics, 18, 4242, Config.floor_gen)
	FloorGenerator.debug_damage = &""
	var root: Node3D = _world()
	Level.build(layout, root)
	var made: int = Hazards.spawn_for_floor()
	assert_eq(made, layout.active_markers.get(&"hazard", PackedStringArray()).size(), "one zone per switched-on hazard marker")
	assert_gt(made, 0, "a destroyed floor 18 has hazards")
	assert_eq(Hazards.spawn_for_floor(), 0, "never twice at one marker")
	Level.clear()
