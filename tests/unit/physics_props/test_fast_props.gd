extends GutTest
## Playtest 2026-10-24: small things (gems, the fuse) thrown hard went through walls. Solo: this PC is the host.

const WALL_X: float = 3.0

var _world: Node3D


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)
	_world.add_child(_box(Vector3(40, 1, 40), Vector3(0, -0.5, 0)))
	# A thin wall, like a room's.
	_world.add_child(_box(Vector3(0.15, 4, 10), Vector3(WALL_X, 2, 0)))
	var props := PropSpawner.new()
	props.name = "Props"
	_world.add_child(props)


func _box(size: Vector3, where: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	body.position = where
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	return body


func _throw_at_wall(prop_id: StringName) -> NetProp:
	var prop: NetProp = Props.spawn_prop(prop_id, Transform3D(Basis.IDENTITY, Vector3(0, 1.5, 0)))
	await wait_physics_frames(2)
	prop.throw_now(Vector3.RIGHT, Props.get_spawner().throw_strength(prop))
	await wait_physics_frames(60)
	return prop


func test_thrown_gem_stays_this_side_of_a_wall() -> void:
	for index: int in 5:
		var gem: NetProp = await _throw_at_wall(&"prop_gem")
		assert_lt(gem.global_position.x, WALL_X, "the gem bounced off the wall")
		Props.despawn(gem)


func test_thrown_fuse_stays_this_side_of_a_wall() -> void:
	for index: int in 5:
		var fuse: NetProp = await _throw_at_wall(&"prop_lift_fuse")
		assert_lt(fuse.global_position.x, WALL_X, "the fuse bounced off the wall")
		Props.despawn(fuse)
