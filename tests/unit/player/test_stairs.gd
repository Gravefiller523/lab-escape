extends GutTest
## Stairs and floors with a real player body (NEW 2026-10-29, HL2 feel step 1.4): walking up 0.2 m and
## 0.4 m steps, being blocked by 0.5 m, staying on the floor walking down, and never stepping onto props.

const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")

var _world: Node3D


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)


func _add_box(center: Vector3, size: Vector3, layer: int = PhysicsLayers.WORLD) -> StaticBody3D:
	var box_body := StaticBody3D.new()
	box_body.collision_layer = PhysicsLayers.bit(layer)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	box_body.add_child(shape)
	box_body.position = center
	_world.add_child(box_body)
	return box_body


## Stairs going forward (-Z) from z = -1: `count` steps of `rise` metres, each 0.5 m deep, then a 6 m landing.
func _add_stairs(rise: float, count: int) -> void:
	for index: int in count:
		var height: float = rise * float(index + 1)
		_add_box(Vector3(0, height * 0.5, -1.25 - 0.5 * index), Vector3(3, height, 0.5))
	var top: float = rise * float(count)
	_add_box(Vector3(0, top * 0.5, -1.0 - 0.5 * count - 3.0), Vector3(3, top, 6))


func _spawn_body() -> PlayerCharacter:
	_add_box(Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	var body := PLAYER_SCENE.instantiate() as PlayerCharacter
	body.player_id = 7
	body.name = "7"
	_world.add_child(body)
	body.set_input_override(PlayerInputState.new())
	await wait_physics_frames(20)
	return body


func _walk_forward(body: PlayerCharacter, seconds: float) -> void:
	var walk := PlayerInputState.new()
	walk.move = Vector2(0, 1)
	body.set_input_override(walk)
	await wait_seconds(seconds)
	body.set_input_override(PlayerInputState.new())


func test_walks_up_low_stairs() -> void:
	_add_stairs(0.2, 5)
	var body: PlayerCharacter = await _spawn_body()
	await _walk_forward(body, 1.5)
	assert_almost_eq(body.global_position.y, 1.0, 0.05, "at the top of 0.2 m stairs")


func test_walks_up_high_stairs() -> void:
	_add_stairs(0.4, 3)
	var body: PlayerCharacter = await _spawn_body()
	await _walk_forward(body, 1.5)
	assert_almost_eq(body.global_position.y, 1.2, 0.05, "at the top of 0.4 m stairs")


func test_half_metre_ledge_blocks() -> void:
	_add_box(Vector3(0, 0.25, -2), Vector3(3, 0.5, 1))
	var body: PlayerCharacter = await _spawn_body()
	await _walk_forward(body, 1.0)
	assert_lt(body.global_position.y, 0.1, "still on the ground")
	assert_gt(body.global_position.z, -1.5, "stopped by the ledge")


func test_does_not_step_onto_props() -> void:
	_add_box(Vector3(0, 0.15, -2), Vector3(3, 0.3, 1), PhysicsLayers.PROPS)
	var body: PlayerCharacter = await _spawn_body()
	await _walk_forward(body, 1.0)
	assert_lt(body.global_position.y, 0.1, "a prop is not a stair")


func test_stays_on_the_floor_walking_down() -> void:
	_add_stairs(0.4, 3)
	var body: PlayerCharacter = await _spawn_body()
	# Start on top and walk back down (backwards keys, facing up the stairs).
	body.global_position = Vector3(0, 1.25, -3.5)
	body.reset_physics_interpolation()
	await wait_physics_frames(10)
	var back := PlayerInputState.new()
	back.move = Vector2(0, -1)
	body.set_input_override(back)
	var airborne_frames: int = 0
	for _frame: int in 60:
		await wait_physics_frames(1)
		if not body.is_on_floor():
			airborne_frames += 1
	assert_lt(body.global_position.y, 0.1, "reached the bottom")
	assert_lt(airborne_frames, 6, "barely leaves the floor on the way down")
