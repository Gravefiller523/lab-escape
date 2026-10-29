extends GutTest
## Footsteps, landing sounds and what floors are made of (NEW 2026-10-29, HL2 feel step 1.7), with a real
## player body. Counts the body's Footsteps.stepped signal.

const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")

var _world: Node3D
var _steps: Array[Dictionary] = []


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)
	_steps.clear()


func _add_box(center: Vector3, size: Vector3) -> StaticBody3D:
	var box_body := StaticBody3D.new()
	box_body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	box_body.add_child(shape)
	box_body.position = center
	_world.add_child(box_body)
	return box_body


func _spawn_body(at: Vector3 = Vector3.ZERO) -> PlayerCharacter:
	var body := PLAYER_SCENE.instantiate() as PlayerCharacter
	body.player_id = 7
	body.name = "7"
	body.position = at
	_world.add_child(body)
	body.set_input_override(PlayerInputState.new())
	body.get_footsteps().stepped.connect(_on_stepped)
	return body


func _on_stepped(surface: SurfaceType, volume_db: float, landing: bool) -> void:
	_steps.append({"surface": surface, "volume_db": volume_db, "landing": landing})


func _count(landing: bool) -> int:
	return _steps.filter(func(step: Dictionary) -> bool: return step["landing"] == landing).size()


func _walk(body: PlayerCharacter, seconds: float, crouch: bool = false) -> void:
	var walk := PlayerInputState.new()
	walk.move = Vector2(0, 1)
	walk.crouch = crouch
	body.set_input_override(walk)
	await wait_seconds(seconds)
	body.set_input_override(PlayerInputState.new())


func test_standing_still_is_silent() -> void:
	_add_box(Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	_spawn_body()
	await wait_seconds(1.0)
	assert_eq(_steps.size(), 0)


func test_walking_makes_steady_footsteps() -> void:
	_add_box(Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	var body: PlayerCharacter = _spawn_body()
	await wait_physics_frames(10)
	await _walk(body, 2.0)
	# About 9 m walked at 1.7 m a step.
	assert_between(_count(false), 4, 7, "footsteps in 2 s of walking (%d)" % _count(false))
	assert_eq(_count(true), 0, "no landings on flat ground")


func test_crouching_is_quieter() -> void:
	_add_box(Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	var body: PlayerCharacter = _spawn_body()
	await wait_physics_frames(10)
	await _walk(body, 2.0, true)
	assert_gt(_steps.size(), 0, "crouch-walking still makes some steps")
	for step: Dictionary in _steps:
		assert_almost_eq(step["volume_db"], body.tuning.footstep_crouch_volume_db, 0.01)


func test_metal_floor_sounds_like_metal() -> void:
	var floor_body: StaticBody3D = _add_box(Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	floor_body.set_meta(&"surface", "metal")
	var body: PlayerCharacter = _spawn_body()
	await wait_physics_frames(10)
	await _walk(body, 1.0)
	assert_gt(_steps.size(), 0)
	assert_eq(_steps[0]["surface"], SurfaceType.find(&"metal"))
	assert_ne(SurfaceType.find(&"metal").step_sound(), SurfaceType.find(&"concrete").step_sound())


func test_falling_three_metres_makes_one_landing() -> void:
	_add_box(Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	_spawn_body(Vector3(0, 3, 0))
	await wait_seconds(1.5)
	assert_eq(_count(true), 1, "one landing sound")


func test_jumping_makes_a_push_off_step() -> void:
	_add_box(Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	var body: PlayerCharacter = _spawn_body()
	await wait_physics_frames(20)
	var jump := PlayerInputState.new()
	jump.jump_pressed = true
	jump.jump_held = true
	body.set_input_override(jump)
	await wait_physics_frames(10)
	body.set_input_override(PlayerInputState.new())
	assert_eq(_count(false), 1, "a step when leaving the floor")
	await wait_seconds(1.0)
	assert_eq(_count(true), 1, "and a landing")
	assert_eq(_count(false), 1, "no extra steps")


func test_surface_comes_from_the_node_or_a_parent() -> void:
	var parent := Node3D.new()
	parent.set_meta(&"surface", "metal")
	var child := Node3D.new()
	parent.add_child(child)
	autofree(parent)
	assert_eq(SurfaceType.of(child), SurfaceType.find(&"metal"))
	assert_eq(SurfaceType.of(null), SurfaceType.find(&"concrete"), "unmarked is concrete")
	assert_eq(SurfaceType.find(&"no_such_thing"), SurfaceType.find(&"concrete"), "unknown is concrete")


func test_quiet_sounds_do_not_cut_off_loud_ones() -> void:
	var long_silence := AudioStreamWAV.new()
	long_silence.format = AudioStreamWAV.FORMAT_16_BITS
	long_silence.mix_rate = 22050
	var data := PackedByteArray()
	data.resize(22050 * 2 * 3)
	long_silence.data = data
	for _index: int in Sound.get_pool_size_3d():
		Sound.play_3d(long_silence, Vector3.ZERO, 0.0)
	await wait_physics_frames(2)
	Sound.play_3d(long_silence, Vector3.ZERO, -20.0)
	var quiet_found: bool = false
	for player: Node in Sound.find_children("*", "AudioStreamPlayer3D", true, false):
		if (player as AudioStreamPlayer3D).playing and is_equal_approx((player as AudioStreamPlayer3D).volume_db, -20.0):
			quiet_found = true
	assert_false(quiet_found, "a quieter sound is skipped when every player is busy")
