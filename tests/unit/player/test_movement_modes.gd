extends GutTest
## Tests for the movement modes (hover, hop, wall_climb, slide) and ladders (docs/systems/player.md).
## Each test builds a small grey-box course and drives a body with set_input_override. The body faces -Z,
## so "forward" (move.y = 1) walks towards -Z.

const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")
const LADDER_SCENE: PackedScene = preload("res://systems/player/ladder.tscn")

var _world: Node3D


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)
	_box(Vector3(40, 1, 40), Vector3(0, -0.5, 0))


func _box(size: Vector3, where: Vector3, tilt_degrees: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	body.position = where
	body.rotation_degrees.x = tilt_degrees
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_world.add_child(body)
	return body


## A wall `height` tall whose front face is at z = -1.5, with a platform on top reaching back to z = -4.
func _wall(height: float) -> void:
	_box(Vector3(6, height, 2.5), Vector3(0, height / 2.0, -2.75))


func _spawn(mode: StringName = &"", jump: float = 1.0, gravity: float = 1.0, speed: float = 1.0,
		can_jump: bool = true, tuning: PlayerTuning = null) -> PlayerCharacter:
	var body := PLAYER_SCENE.instantiate() as PlayerCharacter
	if tuning != null:
		body.tuning = tuning
	body.player_id = 7
	body.name = "7"
	_world.add_child(body)
	if mode != &"" or jump != 1.0 or gravity != 1.0 or speed != 1.0 or not can_jump:
		var effect := MovementEffectData.new()
		effect.movement_mode = mode
		effect.mode_priority = 2
		effect.jump_multiplier = jump
		effect.gravity_multiplier = gravity
		effect.speed_multiplier = speed
		effect.can_jump = can_jump
		body.get_movement().set_modifier(&"test", effect)
	return body


func _keys(forward: float = 0.0, jump: bool = false, held: bool = false, crouch: bool = false) -> PlayerInputState:
	var input := PlayerInputState.new()
	input.move = Vector2(0.0, forward)
	input.jump_pressed = jump
	input.jump_held = held
	input.crouch = crouch
	return input


func _settle(body: PlayerCharacter) -> void:
	body.set_input_override(_keys())
	await wait_physics_frames(15)


func _flat_speed(body: PlayerCharacter) -> float:
	return Vector2(body.velocity.x, body.velocity.z).length()


func test_every_mutation_mode_has_a_file() -> void:
	for content: ContentData in ContentRegistry.get_all(&"mutation"):
		for effect: UpgradeEffectData in (content as UpgradeData).effects:
			var movement := effect as MovementEffectData
			if movement != null and movement.movement_mode != &"":
				assert_not_null(PlayerMovement.load_mode(movement.movement_mode),
					"%s's mode '%s' exists" % [content.id, movement.movement_mode])


# --- Hover (Fly) ---------------------------------------------------------------------------------

func _fall_speed_after_jump(hold: bool) -> float:
	var body := _spawn(&"hover", 1.3, 0.55)
	await _settle(body)
	body.set_input_override(_keys(0.0, true, hold))
	await wait_physics_frames(60)
	var speed: float = -body.velocity.y
	body.queue_free()
	await wait_physics_frames(2)
	return speed


func test_hover_holding_jump_glides_down_slowly() -> void:
	var gliding: float = await _fall_speed_after_jump(true)
	var falling: float = await _fall_speed_after_jump(false)
	var tuning: PlayerTuning = load("res://systems/player/player_tuning.tres")
	assert_lte(gliding, tuning.hover_fall_speed + 0.01, "falls no faster than hover_fall_speed")
	assert_gt(falling, gliding + 1.0, "letting go of jump falls faster")


func test_hover_glide_runs_out_and_refills_on_landing() -> void:
	var tuning := (load("res://systems/player/player_tuning.tres") as PlayerTuning).duplicate() as PlayerTuning
	tuning.hover_seconds = 0.3
	var body := _spawn(&"hover", 1.0, 0.55, 1.0, true, tuning)
	body.global_position.y = 6.0
	body.set_input_override(_keys(0.0, false, true))
	await wait_physics_frames(10)
	var mode := body.get_movement().get_mode_object()
	assert_true(mode.call(&"is_gliding"), "gliding while falling with jump held")
	await wait_physics_frames(30)
	assert_false(mode.call(&"is_gliding"), "out of glide time")
	await wait_until(func() -> bool: return body.is_on_floor(), 5.0)
	body.global_position.y = 4.0
	await wait_physics_frames(10)
	assert_true(mode.call(&"is_gliding"), "landing refilled it")


# --- Hop (Frog) ----------------------------------------------------------------------------------

func test_hop_jump_throws_you_forward() -> void:
	var body := _spawn(&"hop", 1.8)
	body.tuning = body.tuning.duplicate() as PlayerTuning
	body.tuning.hop_auto_hops = false
	await _settle(body)
	body.set_input_override(_keys(1.0))
	await wait_physics_frames(30)
	var walking: float = _flat_speed(body)
	body.set_input_override(_keys(1.0, true))
	await wait_physics_frames(2)
	assert_gt(_flat_speed(body), walking + 2.0, "the jump adds forward speed")
	assert_lte(_flat_speed(body), body.tuning.hop_max_speed + 0.01, "but no faster than hop_max_speed")


func test_hop_moves_in_small_hops() -> void:
	var body := _spawn(&"hop", 1.8)
	await _settle(body)
	body.set_input_override(_keys(1.0))
	var highest: float = 0.0
	for frame: int in 60:
		await wait_physics_frames(1)
		highest = maxf(highest, body.global_position.y)
	assert_gt(highest, 0.1, "walking hops off the ground")
	assert_lt(highest, 0.6, "small hops, not full jumps")
	assert_lt(body.global_position.z, -1.0, "and moves forward")


# --- Wall climb (Octo) ---------------------------------------------------------------------------

func test_wall_climb_goes_up_and_over_a_wall() -> void:
	_wall(2.5)
	var body := _spawn(&"wall_climb", 1.0, 1.0, 1.0, false)
	await _settle(body)
	body.set_input_override(_keys(1.0))
	await wait_until(func() -> bool: return body.global_position.y > 2.4 and body.is_on_floor(), 6.0)
	assert_gt(body.global_position.y, 2.4, "on top of the wall")
	assert_lt(body.global_position.z, -1.6, "over the edge, not hanging on the face")


func test_walking_without_octo_cannot_climb() -> void:
	_wall(2.5)
	var body := _spawn()
	await _settle(body)
	body.set_input_override(_keys(1.0))
	await wait_physics_frames(90)
	assert_lt(body.global_position.y, 0.2, "stays at the bottom")


func test_wall_climb_hangs_on_and_lets_go() -> void:
	_wall(6.0)
	var body := _spawn(&"wall_climb", 1.0, 1.0, 1.0, false)
	await _settle(body)
	body.set_input_override(_keys(1.0))
	await wait_until(func() -> bool: return body.global_position.y > 1.5, 4.0)
	body.set_input_override(_keys(0.0))
	var hanging_at: float = body.global_position.y
	await wait_physics_frames(30)
	assert_almost_eq(body.global_position.y, hanging_at, 0.15, "no keys: hangs on")
	body.set_input_override(_keys(-1.0))
	await wait_physics_frames(20)
	assert_lt(body.global_position.y, hanging_at - 0.3, "S climbs down")
	assert_true(body.get_movement().get_mode_object().call(&"is_climbing"), "still on the wall")
	var climbing_down_at: float = body.global_position.y
	body.set_input_override(_keys(0.0, false, false, true))
	await wait_physics_frames(30)
	assert_false(body.get_movement().get_mode_object().call(&"is_climbing"), "Ctrl lets go")
	assert_lt(body.global_position.y, climbing_down_at - 0.5, "and falls")


# --- Slide (Slug) ---------------------------------------------------------------------------------

func _speed_after_letting_go(mode: StringName) -> float:
	var body := _spawn(mode, 1.0, 1.0, 0.75)
	await _settle(body)
	body.set_input_override(_keys(1.0))
	await wait_physics_frames(90)
	body.set_input_override(_keys())
	await wait_physics_frames(15)
	var speed: float = _flat_speed(body)
	body.queue_free()
	await wait_physics_frames(2)
	return speed


func test_slide_keeps_going_after_letting_go() -> void:
	var sliding: float = await _speed_after_letting_go(&"slide")
	var walking: float = await _speed_after_letting_go(&"")
	assert_gt(sliding, 1.0, "the slug is still sliding")
	assert_gt(sliding, walking + 0.5, "much further than a walker stops")


func test_slide_goes_downhill_on_a_slope() -> void:
	_box(Vector3(10, 0.5, 10), Vector3(0, 1.0, -8), 15.0)
	var body := _spawn(&"slide", 1.0, 1.0, 0.75)
	body.global_position = Vector3(0, 3.5, -10)
	await _settle(body)
	var start_z: float = body.global_position.z
	await wait_physics_frames(60)
	assert_ne(body.global_position.z, start_z, "moved without any keys")
	assert_lte(_flat_speed(body), body.get_movement().get_top_speed() + 0.01, "never faster than its top speed")


# --- Ladders ---------------------------------------------------------------------------------------

## A ladder against the wall's face (front at z = -1.5), facing the body.
func _ladder(height: float) -> Ladder:
	_wall(height)
	var ladder := LADDER_SCENE.instantiate() as Ladder
	ladder.height = height
	ladder.position = Vector3(0, 0, -1.45)
	_world.add_child(ladder)
	return ladder


func test_ladder_climb_up_and_step_off_at_the_top() -> void:
	_ladder(3.0)
	var body := _spawn()
	await _settle(body)
	body.set_input_override(_keys(1.0))
	await wait_until(func() -> bool: return body.get_movement().is_on_ladder(), 3.0)
	assert_eq(body.get_movement().get_active_mode(), PlayerMovement.LADDER_MODE, "climbing")
	await wait_until(func() -> bool: return body.global_position.y > 2.9 and body.is_on_floor(), 5.0)
	assert_gt(body.global_position.y, 2.9, "on top")
	assert_false(body.get_movement().is_on_ladder(), "stepped off the ladder")


func test_ladder_look_down_climbs_down_and_jump_lets_go() -> void:
	_ladder(4.0)
	var body := _spawn()
	await _settle(body)
	body.set_input_override(_keys(1.0))
	await wait_until(func() -> bool: return body.global_position.y > 2.0, 4.0)
	body.set_look_pitch(deg_to_rad(-60.0))
	var high: float = body.global_position.y
	await wait_physics_frames(20)
	assert_lt(body.global_position.y, high - 0.3, "looking down: forward climbs down")
	body.set_look_pitch(0.0)
	body.set_input_override(_keys(0.0, true))
	await wait_physics_frames(3)
	assert_false(body.get_movement().is_on_ladder(), "jumped off")
	assert_gt(body.global_position.z, -1.0, "pushed away from the ladder")


func test_ladder_beats_the_mutation_mode() -> void:
	_ladder(3.0)
	var body := _spawn(&"wall_climb", 1.0, 1.0, 1.0, false)
	await _settle(body)
	body.set_input_override(_keys(1.0))
	await wait_until(func() -> bool: return body.get_movement().is_on_ladder(), 3.0)
	assert_eq(body.get_movement().get_active_mode(), PlayerMovement.LADDER_MODE, "an Octo on a ladder climbs the ladder")


func test_slide_builds_up_speed_to_a_quarter_over_sprint() -> void:
	_box(Vector3(400, 1, 400), Vector3(0, -0.5, 0))
	var body := _spawn(&"slide", 1.0, 1.0, 0.75)
	await _settle(body)
	body.set_input_override(_keys(1.0))
	await wait_seconds(1.5)
	var early: float = _flat_speed(body)
	await wait_seconds(8.0)
	var late: float = _flat_speed(body)
	var top: float = body.tuning.sprint_speed * 1.25
	assert_gt(late, early + 2.0, "keeps getting faster")
	assert_gt(late, body.tuning.sprint_speed, "ends up faster than a normal sprint")
	assert_almost_eq(late, top, 0.3, "tops out at 1.25 x sprint speed")
	assert_almost_eq(body.get_movement().get_top_speed(), top, 0.01, "the host's speed check knows that top speed")
	body.set_input_override(_keys())
	await wait_seconds(2.0)
	assert_eq(body.get_movement().get_mode_object().call(&"get_momentum"), 0.0, "stopping loses the built-up speed")


func test_slide_blocked_by_a_wall_loses_its_speed() -> void:
	_box(Vector3(400, 1, 400), Vector3(0, -0.5, 0))
	var body := _spawn(&"slide", 1.0, 1.0, 0.75)
	await _settle(body)
	body.set_input_override(_keys(1.0))
	await wait_seconds(5.0)
	assert_gt(body.get_movement().get_mode_object().call(&"get_momentum"), 0.5, "built up")
	_box(Vector3(10, 4, 1), body.global_position + Vector3(0, 2, -1.2))
	await wait_seconds(1.0)
	assert_lt(body.get_movement().get_mode_object().call(&"get_momentum"), 0.2, "hitting a wall lost it")
