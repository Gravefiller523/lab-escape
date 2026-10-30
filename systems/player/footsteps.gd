class_name Footsteps
extends RefCounted
## Footstep, jump and landing sounds for one player body (NEW 2026-10-29, HL2 feel step 1.7).
## Works the same for your own body and other players' bodies: it only looks at where the body is each
## physics tick and what is under its feet, so nothing extra is synced. PlayerCharacter owns one and calls
## update() every physics tick. The sound depends on what the floor is made of (SurfaceType).
## NEW 2026-10-30 (HL2 feel step 3.3): on the host, every step and landing is also a noise enemies can hear
## (EventBus.noise_made): crouching is nearly silent, sprinting carries far (Config.feel.ai, "Hearing").

## Played a step (`landing` false) or a landing (`landing` true). Tests listen to this.
signal stepped(surface: SurfaceType, volume_db: float, landing: bool)

## How far below the feet still counts as standing on something, in metres.
const FLOOR_PROBE: float = 0.1
## Moving further than this in one tick is a teleport: no sound.
const TELEPORT_DISTANCE: float = 3.0
## Rising faster than this when leaving the floor counts as a jump (m/s).
const JUMP_RISE_SPEED: float = 2.0
## Shorter airborne spells than this (walking off a small step) don't make a landing sound (seconds).
const MIN_AIR_SECONDS: float = 0.15

var _last_position: Vector3 = Vector3.ZERO
var _has_last: bool = false
var _grounded: bool = true
var _air_seconds: float = 0.0
var _fall_speed: float = 0.0
## Metres walked since the last footstep. Starts half a stride in, so the first step comes quickly.
var _walked: float = 0.0


func update(body: PlayerCharacter, delta: float) -> void:
	var tuning: PlayerTuning = body.tuning
	var position: Vector3 = body.global_position
	if not _has_last or position.distance_to(_last_position) > TELEPORT_DISTANCE or delta <= 0.0:
		_last_position = position
		_has_last = true
		_walked = tuning.footstep_stride * 0.5
		return
	var moved: Vector3 = position - _last_position
	_last_position = position
	var under: Node = _floor_under(body)
	var grounded: bool = under != null
	# Riding something that moves (a cart, a crate): only walking on it counts, not being carried.
	var ride := under as RigidBody3D
	if ride != null:
		moved -= ride.linear_velocity * delta
	var crouching: bool = body.get_movement().crouch_amount > 0.5
	if grounded and not _grounded:
		if _air_seconds >= MIN_AIR_SECONDS and _fall_speed >= tuning.landing_sound_min_speed:
			var louder: float = clampf((_fall_speed - tuning.landing_sound_min_speed) * 1.5, 0.0, 9.0)
			_play(body, under, tuning.footstep_volume_db - 3.0 + louder, true, Config.feel.ai.noise_landing)
		_walked = 0.0
	elif not grounded and _grounded and moved.y / delta > JUMP_RISE_SPEED:
		# Pushing off: a step on whatever was underfoot last tick.
		var below: Node = _floor_under(body, moved.y + FLOOR_PROBE)
		_play(body, below, _volume(tuning, crouching), false, _noise(crouching, false))
	if grounded:
		_air_seconds = 0.0
		_fall_speed = 0.0
		var flat_speed: float = Vector2(moved.x, moved.z).length() / delta
		if flat_speed >= tuning.footstep_min_speed:
			_walked += Vector2(moved.x, moved.z).length()
			var speed_multiplier: float = body.get_movement().get_speed_multiplier()
			var stride: float = _stride(tuning, crouching, flat_speed, speed_multiplier)
			if _walked >= stride:
				_walked = 0.0
				var sprinting: bool = flat_speed > tuning.walk_speed * speed_multiplier * 1.1
				_play(body, under, _volume(tuning, crouching), false, _noise(crouching, sprinting))
	else:
		_air_seconds += delta
		_fall_speed = maxf(-moved.y / delta, 0.0)
	_grounded = grounded


static func _stride(tuning: PlayerTuning, crouching: bool, flat_speed: float, speed_multiplier: float) -> float:
	if crouching:
		return tuning.footstep_crouch_stride
	var walk_top: float = tuning.walk_speed * speed_multiplier
	return tuning.footstep_sprint_stride if flat_speed > walk_top * 1.1 else tuning.footstep_stride


## How far (m) a step carries for enemies.
static func _noise(crouching: bool, sprinting: bool) -> float:
	var ai: AiTuning = Config.feel.ai
	if crouching:
		return ai.noise_crouch_step
	return ai.noise_sprint_step if sprinting else ai.noise_step


static func _volume(tuning: PlayerTuning, crouching: bool) -> float:
	return tuning.footstep_crouch_volume_db if crouching else tuning.footstep_volume_db


## The thing just under the body's feet (level, props or carts), or null in the air.
func _floor_under(body: PlayerCharacter, depth: float = FLOOR_PROBE) -> Node:
	if not body.is_inside_tree():
		return null
	var feet: Vector3 = body.global_position
	var query := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 0.1, feet + Vector3.DOWN * depth,
		PhysicsLayers.bit(PhysicsLayers.WORLD) | PhysicsLayers.bit(PhysicsLayers.PROPS)
		| PhysicsLayers.bit(PhysicsLayers.CARTS))
	query.exclude = [body.get_rid()]
	var hit: Dictionary = body.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("collider") as Node if not hit.is_empty() else null


func _play(body: PlayerCharacter, floor_node: Node, volume_db: float, landing: bool, noise_radius: float) -> void:
	var surface: SurfaceType = SurfaceType.of(floor_node)
	var total_db: float = volume_db + surface.volume_db
	stepped.emit(surface, total_db, landing)
	Sound.play_3d(surface.land_sound() if landing else surface.step_sound(), body.global_position, total_db, 0.08)
	if body.multiplayer.is_server():
		EventBus.noise_made.emit(body.global_position, noise_radius, body.player_id)
