class_name NetProp
extends RigidBody3D
## Root of every prop scene (crates, gems, meat, lift parts...). Spawned only by a PropSpawner.
##
## The host simulates the real physics. Clients' copies are frozen and slide smoothly toward the
## host's snapshots. A client holding a prop moves its own copy straight to its hold point (so holding
## feels instant) while the host pulls the real body there with a spring, so it still collides,
## pushes things and stacks.

signal hold_changed()

## How hard the hold spring pulls (per metre, per kg) and how much it damps.
const HOLD_STIFFNESS: float = 150.0
const HOLD_DAMPING: float = 22.0
## A held prop that stays further than hold_break_distance from its hold point this long is dropped.
const HOLD_BREAK_SECONDS: float = 0.4
## How quickly clients' copies catch up with snapshots, and when they jump instead.
const SNAPSHOT_SMOOTHING: float = 25.0
const SNAPSHOT_SNAP_DISTANCE: float = 3.0
## A resting spot only counts as safe this far above the out-of-world height.
const SAFE_HEIGHT_MARGIN: float = 5.0
## A push counts for this long after the last report (milliseconds), so pushes don't flicker.
const PUSH_MEMORY_MSEC: int = 250
## Pushed props move a little slower than the pusher, so the pusher stays pressed against them.
const PUSH_SPEED_FACTOR: float = 0.9
## Snapshots kept per prop on clients.
const MAX_SNAPSHOTS: int = 12

## Unique per spawned prop, set by the host.
var net_id: int = 0
## Content id, e.g. &"prop_crate".
var content_id: StringName = &""
## The prop's data (mass, key object...). Null for item pickups.
var data: PropData
## Last player who held or threw it (vendors use it to know who pays). 0 = nobody yet.
var last_holder_id: int = 0
## Spawn data (e.g. {"upgrade_id": &"mutation_fly"}).
var extra: Dictionary = {}

var _holders: Array[int] = []
var _spawner: PropSpawner
var _anchor: Node3D
## Clients: the latest snapshot from the host.
## Clients: recent snapshots from the host, oldest first: {"t": host msec, "p": Vector3, "r": Quaternion}.
var _snapshots: Array[Dictionary] = []
## Clients: while this PC is pushing it, move it here straight away instead of waiting for the host.
var _push_predict_until_msec: int = 0
var _push_predict_velocity: Vector3 = Vector3.ZERO
## The local holder's predicted hold point (clients and host alike); null-like when not predicting.
var _predicting: bool = false
var _predicted_target: Vector3
## Host: where each holder wants it (player id -> point).
var _hold_targets: Dictionary[int, Vector3] = {}
## Host: last place it was resting safely (for key objects).
var _safe_position: Vector3
var _stuck_seconds: float = 0.0
## Holders' bodies we ignore collisions with.
var _excepted_bodies: Array[PlayerCharacter] = []
## Host: players pushing it right now (player id -> {time, direction, speed}).
var _pushes: Dictionary[int, Dictionary] = {}


## The NetProp a node belongs to (the prop itself, or one of its children). Null if none.
static func of(node: Node) -> NetProp:
	var current: Node = node
	while current != null:
		if current is NetProp:
			return current as NetProp
		current = current.get_parent()
	return null


func _ready() -> void:
	collision_layer = PhysicsLayers.bit(PhysicsLayers.PROPS)
	# Not PLAYERS: players bump into props (their mask has PROPS) but can't shove them through walls
	# just by walking into them. Players move props by holding them.
	collision_mask = PhysicsLayers.bit(PhysicsLayers.WORLD) | PhysicsLayers.bit(PhysicsLayers.PROPS) \
		| PhysicsLayers.bit(PhysicsLayers.CARTS) | PhysicsLayers.bit(PhysicsLayers.ENEMIES)
	if data != null:
		mass = data.mass
	_safe_position = global_position
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	# Only the host simulates. Clients follow snapshots.
	freeze = not multiplayer.is_server()
	sleeping_state_changed.connect(_on_sleeping_state_changed)


func is_held() -> bool:
	return not _holders.is_empty()


## Who is holding it: one player, or two for a shared heavy lift.
func get_holder_ids() -> Array[int]:
	return _holders.duplicate()


## True when two people must lift it together (heavier than one player can carry).
## True for heavy props (above grab_max_mass): one person can only drag them slowly; helpers speed it up.
func needs_help() -> bool:
	return mass > _config().grab_max_mass


## How much of its weight its holders carry, 0 to 1. Normal props: 1 while held. Heavy props: each
## holder takes heavy_lift_per_holder kg off (1 holder of an 80 kg crate: 30/80 = 0.375).
func get_support() -> float:
	return support_for(_holders.size())


## How much of its weight `people` holders (or pushers) can move, 0 to 1 (see get_support).
func support_for(people: int) -> float:
	if people <= 0:
		return 0.0
	if not needs_help():
		return 1.0
	return clampf(float(people) * _config().heavy_lift_per_holder / mass, 0.0, 1.0)


## Host: a player walking into this prop pushes it along `direction` at up to `speed` m/s, slowed by
## its weight the same way carrying is (light props move at full speed, heavy ones barely).
func add_push(player_id: int, direction: Vector3, speed: float) -> void:
	_pushes[player_id] = {"time": Time.get_ticks_msec(), "direction": direction, "speed": speed}


## True while it is fully off the ground in its holders' hands.
func is_lifted() -> bool:
	return get_support() >= 1.0


func _config() -> GameConfig:
	return _spawner.get_config() if _spawner != null else Config.game


## Snapped into a cart, vendor or lift.
func is_attached() -> bool:
	return _anchor != null


## Host: freeze it and make it follow `anchor` (carts, vendor trays).
func attach_to(anchor: Node3D) -> void:
	if not multiplayer.is_server():
		return
	_anchor = anchor
	freeze = true


## Host: physics back on.
func detach() -> void:
	if not multiplayer.is_server():
		return
	_anchor = null
	freeze = false


## The spawner that made this prop.
func get_spawner() -> PropSpawner:
	return _spawner


# --- Internal to physics_props (PropSpawner and GrabController call these; other systems don't) ---

## Where a key object goes back to if it falls out of the world.
func get_safe_position() -> Vector3:
	return _safe_position


func set_spawner(spawner: PropSpawner) -> void:
	_spawner = spawner


func apply_holders(holders: Array[int], last_holder: int) -> void:
	_holders = holders.duplicate()
	if last_holder != 0:
		last_holder_id = last_holder
	for player_id: int in _hold_targets.keys():
		if not _holders.has(player_id):
			_hold_targets.erase(player_id)
	if multiplayer.is_server():
		# The holders carry part (or all) of its weight; the rest still pulls it down.
		gravity_scale = 1.0 - get_support()
		angular_damp = 8.0 if is_held() else 0.0
	_update_holder_exceptions()
	hold_changed.emit()


## Holders don't collide with what they hold (no standing on it, no pushing yourself with it).
func _update_holder_exceptions() -> void:
	if _spawner == null:
		return
	var holder_bodies: Array[PlayerCharacter] = []
	for player_id: int in _holders:
		var body: PlayerCharacter = _spawner.get_body_of_player(player_id)
		if body != null:
			holder_bodies.append(body)
	for body: PlayerCharacter in _excepted_bodies:
		if is_instance_valid(body) and not holder_bodies.has(body):
			remove_collision_exception_with(body)
	for body: PlayerCharacter in holder_bodies:
		add_collision_exception_with(body)
	_excepted_bodies = holder_bodies


## Clients: a snapshot from the host, stamped with the host's clock (milliseconds).
func apply_snapshot(host_msec: int, position_now: Vector3, rotation_now: Quaternion) -> void:
	if not _snapshots.is_empty() and host_msec <= int(_snapshots.back()["t"]):
		return
	_snapshots.append({"t": host_msec, "p": position_now, "r": rotation_now})
	while _snapshots.size() > MAX_SNAPSHOTS:
		_snapshots.pop_front()


## Clients: this PC is pushing it; move it now (the host does the same a moment later).
func predict_push(velocity: Vector3) -> void:
	_push_predict_velocity = velocity
	_push_predict_until_msec = Time.get_ticks_msec() + PUSH_MEMORY_MSEC


func start_predicting(target: Vector3) -> void:
	_predicting = true
	_predicted_target = target


func stop_predicting() -> void:
	_predicting = false


func set_hold_target(player_id: int, target: Vector3) -> void:
	if _holders.has(player_id):
		_hold_targets[player_id] = target


func _physics_process(delta: float) -> void:
	if _anchor != null:
		if is_instance_valid(_anchor):
			global_transform = _anchor.global_transform
		else:
			_anchor = null
			freeze = not multiplayer.is_server()
		return
	if multiplayer.is_server():
		_host_update(delta)
	else:
		_client_update(delta)


## Host: pull a lifted prop toward its holders' hold point with a spring, and drop it if stuck.
## Heavy props that aren't fully lifted are pulled more weakly and more slowly (they drag).
func _host_update(delta: float) -> void:
	_apply_pushes()
	var support: float = get_support()
	if support <= 0.0 or _hold_targets.is_empty():
		_stuck_seconds = 0.0
		return
	var target := Vector3.ZERO
	for point: Vector3 in _hold_targets.values():
		target += point
	target /= float(_hold_targets.size())
	var config: GameConfig = _spawner.get_config()
	var offset: Vector3 = target - global_position
	# A spring that grows with mass, plus damping so it settles instead of wobbling.
	apply_central_force((offset * HOLD_STIFFNESS - linear_velocity * HOLD_DAMPING) * mass * support)
	var max_speed: float = config.held_prop_max_speed * support
	if linear_velocity.length() > max_speed:
		linear_velocity = linear_velocity.limit_length(max_speed)
	if support >= 1.0 and offset.length() > config.hold_break_distance:
		_stuck_seconds += delta
		if _stuck_seconds > HOLD_BREAK_SECONDS:
			_stuck_seconds = 0.0
			_spawner.release_all(self)
	else:
		_stuck_seconds = 0.0


## Host: players walking into it right now push it. More pushers = faster, like more holders.
func _apply_pushes() -> void:
	if _pushes.is_empty() or is_held():
		_pushes.clear()
		return
	var now: int = Time.get_ticks_msec()
	var direction := Vector3.ZERO
	var speed: float = 0.0
	for player_id: int in _pushes.keys():
		var push: Dictionary = _pushes[player_id]
		if now - int(push["time"]) > PUSH_MEMORY_MSEC:
			_pushes.erase(player_id)
			continue
		direction += push["direction"] as Vector3
		speed = maxf(speed, float(push["speed"]))
	if _pushes.is_empty() or direction.is_zero_approx():
		return
	direction = Vector3(direction.x, 0.0, direction.z).normalized()
	var wanted: float = speed * PUSH_SPEED_FACTOR * support_for(_pushes.size())
	var current: float = linear_velocity.dot(direction)
	if current < wanted:
		linear_velocity += direction * (wanted - current)
		sleeping = false


## Client: the local holder moves its copy to the hold point; everyone else follows snapshots.
func _client_update(delta: float) -> void:
	if _predicting:
		var motion: Vector3 = _predicted_target - global_position
		# Stop at walls instead of passing through them.
		var collision: KinematicCollision3D = move_and_collide(motion, false, 0.001, true)
		if collision != null:
			global_position += collision.get_travel()
		return
	if Time.get_ticks_msec() < _push_predict_until_msec:
		var push_motion: Vector3 = _push_predict_velocity * delta
		var push_hit: KinematicCollision3D = move_and_collide(push_motion, false, 0.001, true)
		global_position += push_hit.get_travel() if push_hit != null else push_motion
		return
	if _snapshots.is_empty() or _spawner == null:
		return
	# Show where the host had it a moment ago (interpolation delay), between two snapshots, so
	# movement is even instead of hopping from snapshot to snapshot.
	var render_msec: int = _spawner.get_host_clock_msec() - _spawner.get_config().prop_interpolation_delay_msec
	var target_position: Vector3 = _snapshots.back()["p"]
	var target_rotation: Quaternion = _snapshots.back()["r"]
	for index: int in range(_snapshots.size() - 1):
		var before: Dictionary = _snapshots[index]
		var after: Dictionary = _snapshots[index + 1]
		if int(before["t"]) <= render_msec and render_msec <= int(after["t"]):
			var span: float = maxf(float(int(after["t"]) - int(before["t"])), 1.0)
			var t: float = float(render_msec - int(before["t"])) / span
			target_position = (before["p"] as Vector3).lerp(after["p"] as Vector3, t)
			target_rotation = (before["r"] as Quaternion).slerp(after["r"] as Quaternion, t)
			break
	if global_position.distance_to(target_position) > SNAPSHOT_SNAP_DISTANCE:
		global_position = target_position
		global_basis = Basis(target_rotation)
		return
	# A short glide hides small differences (e.g. after our own push prediction ends).
	var weight: float = 1.0 - exp(-SNAPSHOT_SMOOTHING * delta)
	global_position = global_position.lerp(target_position, weight)
	global_basis = Basis(global_basis.get_rotation_quaternion().slerp(target_rotation, weight))


func _on_sleeping_state_changed() -> void:
	if sleeping and multiplayer.is_server() and _spawner != null \
			and global_position.y > _spawner.get_config().out_of_world_y + SAFE_HEIGHT_MARGIN:
		_safe_position = global_position

