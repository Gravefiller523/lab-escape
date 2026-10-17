extends GutTest
## Tests for the player's movement modifiers, modes and body (docs/systems/player.md).

const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")

var _world: Node3D


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)


func _effect(speed: float = 1.0, can_jump: bool = true, mode: StringName = &"", priority: int = 0) -> MovementEffectData:
	var effect := MovementEffectData.new()
	effect.speed_multiplier = speed
	effect.can_jump = can_jump
	effect.movement_mode = mode
	effect.mode_priority = priority
	return effect


## A body standing on a floor, controlled by this PC.
func _spawn_body(player_id: int = 7) -> PlayerCharacter:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	_world.add_child(floor_body)
	var body := PLAYER_SCENE.instantiate() as PlayerCharacter
	body.player_id = player_id
	body.name = str(player_id)
	_world.add_child(body)
	return body


func _settle(body: PlayerCharacter) -> void:
	body.set_input_override(PlayerInputState.new())
	await wait_physics_frames(20)


func test_modifiers_multiply() -> void:
	var movement := PlayerMovement.new()
	add_child_autofree(movement)
	movement.set_modifier(&"a", _effect(1.5))
	movement.set_modifier(&"b", _effect(2.0))
	assert_almost_eq(movement.get_speed_multiplier(), 3.0, 0.001)


func test_highest_priority_mode_wins() -> void:
	var movement := PlayerMovement.new()
	add_child_autofree(movement)
	movement.set_modifier(&"slug", _effect(1.0, true, &"slide", 1))
	movement.set_modifier(&"octo", _effect(1.0, true, &"wall_climb", 5))
	assert_eq(movement.get_wanted_mode(), &"wall_climb")


func test_missing_mode_file_falls_back_to_walk() -> void:
	var movement := PlayerMovement.new()
	add_child_autofree(movement)
	movement.set_modifier(&"test", _effect(1.0, true, &"mode_that_does_not_exist", 1))
	assert_eq(movement.get_active_mode(), PlayerMovement.DEFAULT_MODE)


func test_can_jump_false_blocks_jump() -> void:
	var body := _spawn_body()
	await _settle(body)
	assert_true(body.is_on_floor(), "standing on the floor")
	body.get_movement().set_modifier(&"test", _effect(1.0, false))
	var jump := PlayerInputState.new()
	jump.jump_pressed = true
	body.set_input_override(jump)
	await wait_physics_frames(5)
	assert_lt(body.global_position.y, 0.05, "stays on the ground")

	body.get_movement().remove_modifier(&"test")
	jump = PlayerInputState.new()
	jump.jump_pressed = true
	body.set_input_override(jump)
	await wait_physics_frames(10)
	assert_gt(body.global_position.y, 0.2, "jumps again without the modifier")


func test_remove_modifier_restores_defaults() -> void:
	var movement := PlayerMovement.new()
	add_child_autofree(movement)
	movement.set_modifier(&"test", _effect(2.0, false, &"slide", 3))
	movement.remove_modifier(&"test")
	assert_almost_eq(movement.get_speed_multiplier(), 1.0, 0.001)
	assert_true(movement.can_jump())
	assert_eq(movement.get_wanted_mode(), PlayerMovement.DEFAULT_MODE)


func test_mode_file_found_by_name() -> void:
	var mode: MovementMode = PlayerMovement.load_mode(&"walk")
	assert_not_null(mode, "movement_modes/walk_mode.gd is found from the name")
	assert_null(PlayerMovement.load_mode(&"mode_that_does_not_exist"))


func test_find_by_player_id() -> void:
	var body := _spawn_body(42)
	assert_eq(PlayerCharacter.find(42), body)
	assert_null(PlayerCharacter.find(43))
	assert_eq(PlayerCharacter.of(body.get_hold_point()), body, "of() climbs up from a child")
	assert_not_null(body.get_attach_point(&"head"))


func test_walking_moves_forward() -> void:
	var body := _spawn_body()
	await _settle(body)
	var start: Vector3 = body.global_position
	var walk := PlayerInputState.new()
	walk.move = Vector2(0, 1)
	body.set_input_override(walk)
	await wait_physics_frames(30)
	assert_lt(body.global_position.z, start.z - 1.0, "forward is -Z")


func test_crouch_lowers_height_and_stands_back_up() -> void:
	var body := _spawn_body()
	await _settle(body)
	var standing: float = body.get_movement().get_height()
	var crouch := PlayerInputState.new()
	crouch.crouch = true
	body.set_input_override(crouch)
	await wait_physics_frames(30)
	assert_true(body.get_movement().is_crouching())
	assert_lt(body.get_movement().get_height(), standing)
	body.set_input_override(PlayerInputState.new())
	await wait_physics_frames(30)
	assert_almost_eq(body.get_movement().get_height(), standing, 0.01)


func test_height_multiplier_makes_body_taller() -> void:
	var body := _spawn_body()
	var normal: float = body.get_movement().get_height()
	var giraffe := MovementEffectData.new()
	giraffe.height_multiplier = 1.5
	body.get_movement().set_modifier(&"giraffe", giraffe)
	assert_almost_eq(body.get_movement().get_height(), normal * 1.5, 0.01)
