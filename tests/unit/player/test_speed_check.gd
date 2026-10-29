extends GutTest
## The host's speed check on other players' bodies (NEW 2026-10-29, HL2 feel step 1.8): bunny hopping and
## air strafing may build speed gradually, but sudden bursts, teleports and going past the cap are put back.
## The body belongs to player 7, so on this (host) PC it is someone else's body, following sync_position.

const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")

var _world: Node3D


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.5, 0)
	_world.add_child(floor_body)


func _spawn_remote_body() -> PlayerCharacter:
	var body := PLAYER_SCENE.instantiate() as PlayerCharacter
	body.player_id = 7
	body.name = "7"
	body.set_multiplayer_authority(7)
	_world.add_child(body)
	await wait_physics_frames(5)
	return body


## Moves the body's synced position along +X by `distance_at(seconds)` for `seconds`, as its owner would.
## Returns how many times the host put it back.
func _drive(body: PlayerCharacter, distance_at: Callable, seconds: float) -> int:
	var start: Vector3 = body.sync_position
	var first_frame: int = Engine.get_physics_frames()
	var snaps: int = 0
	var expected: Vector3 = start
	while true:
		await wait_physics_frames(1)
		if not body.sync_position.is_equal_approx(expected):
			snaps += 1
		var t: float = float(Engine.get_physics_frames() - first_frame) / float(Engine.physics_ticks_per_second)
		if t > seconds:
			break
		expected = start + Vector3(distance_at.call(t), 0.0, 0.0)
		body.sync_position = expected
	_ignore_offline_message_errors()
	return snaps


## There is no player 7 connected in a test, so each "go back" message the host sends them fails with an
## engine error. The test counts the put-backs on the host's side instead.
func _ignore_offline_message_errors() -> void:
	for tracked: Variant in get_errors():
		if tracked.is_engine_error():
			tracked.handled = true


func test_steady_sprinting_is_fine() -> void:
	var body: PlayerCharacter = await _spawn_remote_body()
	var snaps: int = await _drive(body, func(t: float) -> float: return 7.5 * t, 2.0)
	assert_eq(snaps, 0)


func test_bunny_hop_speed_builds_up_without_being_put_back() -> void:
	var body: PlayerCharacter = await _spawn_remote_body()
	# 7.5 m/s gaining 4 m/s every second for 2 s (to 15.5), then holding that for a second.
	var hop := func(t: float) -> float:
		var ramp: float = minf(t, 2.0)
		return 7.5 * ramp + 2.0 * ramp * ramp + maxf(t - 2.0, 0.0) * 15.5
	var snaps: int = await _drive(body, hop, 3.0)
	assert_eq(snaps, 0, "twice sprint speed, reached gradually, is allowed")


func test_sudden_burst_is_put_back() -> void:
	var body: PlayerCharacter = await _spawn_remote_body()
	await _drive(body, func(_t: float) -> float: return 0.0, 1.0)
	var snaps: int = await _drive(body, func(t: float) -> float: return 20.0 * t, 1.0)
	assert_gt(snaps, 0, "20 m/s from standing")


func test_teleporting_is_put_back() -> void:
	var body: PlayerCharacter = await _spawn_remote_body()
	await _drive(body, func(_t: float) -> float: return 0.0, 0.6)
	var snaps: int = await _drive(body, func(_t: float) -> float: return 5.0, 0.2)
	assert_gt(snaps, 0)


func test_nobody_goes_past_the_cap() -> void:
	var body: PlayerCharacter = await _spawn_remote_body()
	# Gains 6 m/s every second up to 30 m/s, then holds it.
	var runaway := func(t: float) -> float:
		var ramp: float = minf(t, 3.75)
		return 7.5 * ramp + 3.0 * ramp * ramp + maxf(t - 3.75, 0.0) * 30.0
	var snaps: int = await _drive(body, runaway, 5.0)
	assert_gt(snaps, 0, "30 m/s is past the %.1f m/s cap" % body.tuning.speed_check_max_speed)
