extends GutTest
## Jumping with a real player body (NEW 2026-10-29, HL2 feel step 1.2): jump buffer, coyote time, keeping
## momentum in the air, jumping while crouched and no auto-hop from holding jump.

const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")

var _world: Node3D


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)


func _add_box(center: Vector3, size: Vector3) -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = center
	_world.add_child(floor_body)


## A body on a big floor (top at y = 0), or on a 4 m wide ledge 3 m above a lower floor.
func _spawn_body(on_ledge: bool = false) -> PlayerCharacter:
	if on_ledge:
		_add_box(Vector3(0, -0.5, 0), Vector3(4, 1, 4))
		_add_box(Vector3(0, -3.5, 0), Vector3(60, 1, 60))
	else:
		_add_box(Vector3(0, -0.5, 0), Vector3(60, 1, 60))
	var body := PLAYER_SCENE.instantiate() as PlayerCharacter
	body.player_id = 7
	body.name = "7"
	_world.add_child(body)
	body.set_input_override(_keys())
	await wait_physics_frames(20)
	return body


func _keys(forward: float = 0.0, jump: bool = false, held: bool = false, crouch: bool = false) -> PlayerInputState:
	var input := PlayerInputState.new()
	input.move = Vector2(0, forward)
	input.jump_pressed = jump
	input.jump_held = held or jump
	input.crouch = crouch
	return input


func _flat_speed(body: PlayerCharacter) -> float:
	return Vector2(body.velocity.x, body.velocity.z).length()


func test_momentum_carries_through_the_air() -> void:
	var body: PlayerCharacter = await _spawn_body()
	body.set_input_override(_keys(1.0))
	await wait_physics_frames(30)
	var running: float = _flat_speed(body)
	body.set_input_override(_keys(1.0, true))
	await wait_physics_frames(2)
	body.set_input_override(_keys())
	await wait_physics_frames(15)
	assert_false(body.is_on_floor(), "still in the air")
	assert_almost_eq(_flat_speed(body), running, running * 0.05, "letting go in the air doesn't brake")


func test_jump_pressed_just_before_landing_still_jumps() -> void:
	var body: PlayerCharacter = await _spawn_body()
	var ground_y: float = body.global_position.y
	body.set_input_override(_keys(0.0, true))
	await wait_until(func() -> bool: return body.velocity.y < 0.0 and body.global_position.y < ground_y + 0.3, 2.0)
	assert_false(body.is_on_floor(), "pressed while still falling")
	body.set_input_override(_keys(0.0, true))
	await wait_until(func() -> bool: return body.velocity.y > 0.0, 0.5)
	assert_gt(body.velocity.y, 0.0, "jumped again on landing")


func test_late_jump_after_walking_off_a_ledge() -> void:
	var body: PlayerCharacter = await _spawn_body(true)
	body.set_input_override(_keys(1.0))
	await wait_until(func() -> bool: return not body.is_on_floor(), 3.0)
	body.set_input_override(_keys(1.0, true))
	await wait_physics_frames(3)
	assert_gt(body.velocity.y, 0.0, "coyote time: the late jump works")


func test_too_late_after_walking_off_a_ledge() -> void:
	var body: PlayerCharacter = await _spawn_body(true)
	body.set_input_override(_keys(1.0))
	await wait_until(func() -> bool: return not body.is_on_floor(), 3.0)
	await wait_seconds(body.tuning.coyote_seconds + 0.1)
	body.set_input_override(_keys(1.0, true))
	await wait_physics_frames(3)
	assert_lt(body.velocity.y, 0.0, "past coyote time: still falling")


func test_can_jump_while_crouched() -> void:
	var body: PlayerCharacter = await _spawn_body()
	body.set_input_override(_keys(0.0, false, false, true))
	await wait_physics_frames(20)
	assert_true(body.get_movement().is_crouching())
	var ground_y: float = body.global_position.y
	body.set_input_override(_keys(0.0, true, false, true))
	await wait_physics_frames(10)
	assert_gt(body.global_position.y, ground_y + 0.2, "jumped while crouched")


func test_holding_jump_does_not_hop_again() -> void:
	var body: PlayerCharacter = await _spawn_body()
	body.set_input_override(_keys(0.0, true))
	await wait_until(func() -> bool: return body.velocity.y < 0.0, 2.0)
	await wait_until(func() -> bool: return body.is_on_floor(), 2.0)
	await wait_physics_frames(30)
	assert_true(body.is_on_floor(), "held jump: stays down after landing")


## Highest the feet get in one jump, with or without crouching straight after take-off.
func _jump_apex(crouch: bool) -> float:
	var body: PlayerCharacter = await _spawn_body()
	var ground_y: float = body.global_position.y
	# Jump, then crouch once off the ground (crouching on the ground would lower the head instead).
	body.set_input_override(_keys(0.0, true))
	await wait_physics_frames(1)
	body.set_input_override(_keys(0.0, false, false, crouch))
	var apex: float = ground_y
	for _frame: int in 50:
		await wait_physics_frames(1)
		apex = maxf(apex, body.global_position.y)
	body.queue_free()
	return apex - ground_y


func test_crouch_jump_lifts_the_feet() -> void:
	var standing: float = await _jump_apex(false)
	var crouched: float = await _jump_apex(true)
	var tuning: PlayerTuning = Config.feel.player
	var tuck: float = tuning.stand_height - tuning.crouch_height
	assert_almost_eq(crouched - standing, tuck, 0.1, "crouching in the air lifts the feet by the crouch amount")


func test_crouch_jump_onto_a_ledge() -> void:
	var body: PlayerCharacter = await _spawn_body()
	_add_box(Vector3(0, 0.7, -2.5), Vector3(3, 1.4, 2))
	body.set_input_override(_keys(1.0))
	await wait_physics_frames(6)
	body.set_input_override(_keys(1.0, true))
	await wait_physics_frames(1)
	body.set_input_override(_keys(1.0, false, false, true))
	await wait_seconds(1.0)
	assert_gt(body.global_position.y, 1.3, "up on the 1.4 m ledge")
