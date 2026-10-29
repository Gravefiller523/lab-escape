extends GutTest
## Feel metrics (NEW 2026-10-29, HL2 feel step 0.4). Drives a real player body on a flat floor and prints
## the numbers that describe how movement feels: time to top speed, stopping time and jump height.
## Look for the "[feel]" lines in the GUT output and compare them before and after a movement change.
## The checks are loose on purpose: they catch broken movement, not small tuning changes.

const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")
## Give up measuring after this many physics frames (5 s at 60 Hz).
const MAX_FRAMES: int = 300
## "At top speed" means within this fraction of it.
const NEAR_TOP: float = 0.95
## "Stopped" means slower than this, in m/s.
const STOPPED_SPEED: float = 0.1

var _world: Node3D


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)


func _spawn_body() -> PlayerCharacter:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	_world.add_child(floor_body)
	var body := PLAYER_SCENE.instantiate() as PlayerCharacter
	body.player_id = 7
	body.name = "7"
	_world.add_child(body)
	return body


func _make_input(move: Vector2 = Vector2.ZERO, sprint: bool = false, jump: bool = false) -> PlayerInputState:
	var input := PlayerInputState.new()
	input.move = move
	input.sprint = sprint
	input.jump_pressed = jump
	input.jump_held = jump
	return input


func _flat_speed(body: PlayerCharacter) -> float:
	return Vector2(body.velocity.x, body.velocity.z).length()


## Seconds of game time since the physics frame count was `start_frame` (GUT's waits can span more than
## one physics frame, so count the engine's own frames).
func _seconds_since(start_frame: int) -> float:
	return float(Engine.get_physics_frames() - start_frame) / float(Engine.physics_ticks_per_second)


func _report(label: String, value: float, unit: String) -> void:
	var line: String = "[feel] %s: %.3f %s" % [label, value, unit]
	gut.p(line)
	print(line)


## Seconds until the body's flat speed is within NEAR_TOP of `top`, or -1.
func _seconds_to_reach(body: PlayerCharacter, top: float) -> float:
	var start: int = Engine.get_physics_frames()
	for _frame: int in MAX_FRAMES:
		await wait_physics_frames(1)
		if _flat_speed(body) >= top * NEAR_TOP:
			return _seconds_since(start)
	return -1.0


func _settle(body: PlayerCharacter) -> void:
	body.set_input_override(_make_input())
	await wait_physics_frames(20)


func test_walk_and_sprint_time_to_top_speed() -> void:
	var tuning: PlayerTuning = Config.feel.player
	var body := _spawn_body()
	await _settle(body)
	body.set_input_override(_make_input(Vector2(0, 1)))
	var walk_seconds: float = await _seconds_to_reach(body, tuning.walk_speed)
	assert_gt(walk_seconds, 0.0, "reaches walk speed")
	_report("time to walk speed (%.2f m/s)" % tuning.walk_speed, walk_seconds, "s")

	await _settle(body)
	await wait_until(func() -> bool: return _flat_speed(body) < STOPPED_SPEED, 3.0)
	body.set_input_override(_make_input(Vector2(0, 1), true))
	var sprint_seconds: float = await _seconds_to_reach(body, tuning.sprint_speed)
	assert_gt(sprint_seconds, 0.0, "reaches sprint speed")
	_report("time to sprint speed (%.2f m/s)" % tuning.sprint_speed, sprint_seconds, "s")


func test_stopping_time_from_walk_and_sprint() -> void:
	var tuning: PlayerTuning = Config.feel.player
	var body := _spawn_body()
	await _settle(body)
	for sprint: bool in [false, true]:
		var top: float = tuning.sprint_speed if sprint else tuning.walk_speed
		body.set_input_override(_make_input(Vector2(0, 1), sprint))
		assert_gt(await _seconds_to_reach(body, top), 0.0, "gets up to speed first")
		await wait_physics_frames(10)
		body.set_input_override(_make_input())
		var start_z: float = body.global_position.z
		var start: int = Engine.get_physics_frames()
		var seconds: float = -1.0
		for _frame: int in MAX_FRAMES:
			await wait_physics_frames(1)
			if _flat_speed(body) < STOPPED_SPEED:
				seconds = _seconds_since(start)
				break
		assert_gt(seconds, 0.0, "comes to a stop")
		var gait: String = "sprint" if sprint else "walk"
		_report("stop time from %s" % gait, seconds, "s")
		_report("slide distance from %s" % gait, absf(body.global_position.z - start_z), "m")


func test_standing_jump_height_and_air_time() -> void:
	var tuning: PlayerTuning = Config.feel.player
	var body := _spawn_body()
	await _settle(body)
	var ground_y: float = body.global_position.y
	var start: int = Engine.get_physics_frames()
	body.set_input_override(_make_input(Vector2.ZERO, false, true))
	await wait_physics_frames(1)
	body.set_input_override(_make_input())
	var apex: float = ground_y
	var seconds: float = -1.0
	for _frame: int in MAX_FRAMES:
		await wait_physics_frames(1)
		apex = maxf(apex, body.global_position.y)
		# Back down at ground height (is_on_floor() alone can read true near the top of the jump).
		if apex > ground_y + 0.1 and body.global_position.y <= ground_y + 0.02:
			seconds = _seconds_since(start)
			break
	var height: float = apex - ground_y
	_report("standing jump height (tuning says %.2f m)" % tuning.jump_height, height, "m")
	_report("standing jump air time", seconds, "s")
	assert_gt(seconds, 0.0, "lands again")
	assert_almost_eq(height, tuning.jump_height, tuning.jump_height * 0.1, "jump height within 10% of the tuning")
