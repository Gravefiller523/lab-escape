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
const SNAPSHOT_SMOOTHING: float = 18.0
const SNAPSHOT_SNAP_DISTANCE: float = 3.0
## A resting spot only counts as safe this far above the out-of-world height.
const SAFE_HEIGHT_MARGIN: float = 5.0

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
var _snap_position: Vector3
var _snap_rotation: Quaternion
var _has_snapshot: bool = false
## The local holder's predicted hold point (clients and host alike); null-like when not predicting.
var _predicting: bool = false
var _predicted_target: Vector3
## Host: where each holder wants it (player id -> point).
var _hold_targets: Dictionary[int, Vector3] = {}
## Host: last place it was resting safely (for key objects).
var _safe_position: Vector3
var _stuck_seconds: float = 0.0


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
	collision_mask = PhysicsLayers.bit(PhysicsLayers.WORLD) | PhysicsLayers.bit(PhysicsLayers.PLAYERS) \
		| PhysicsLayers.bit(PhysicsLayers.PROPS) | PhysicsLayers.bit(PhysicsLayers.CARTS) \
		| PhysicsLayers.bit(PhysicsLayers.ENEMIES)
	if data != null:
		mass = data.mass
	_safe_position = global_position
	_snap_position = global_position
	_snap_rotation = global_basis.get_rotation_quaternion()
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
func needs_two_people() -> bool:
	return mass > _spawner.get_config().grab_max_mass if _spawner != null else mass > Config.game.grab_max_mass


## True while it is actually off the ground in someone's hands (a heavy prop needs both holders).
func is_lifted() -> bool:
	return _holders.size() >= (2 if needs_two_people() else 1)


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
		# Lifted props float (the spring holds them up); everything else falls normally.
		gravity_scale = 0.0 if is_lifted() else 1.0
		angular_damp = 8.0 if is_lifted() else 0.0
	hold_changed.emit()


func apply_snapshot(position_now: Vector3, rotation_now: Quaternion) -> void:
	_snap_position = position_now
	_snap_rotation = rotation_now
	_has_snapshot = true


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
func _host_update(delta: float) -> void:
	if not is_lifted() or _hold_targets.is_empty():
		_stuck_seconds = 0.0
		return
	var target := Vector3.ZERO
	for point: Vector3 in _hold_targets.values():
		target += point
	target /= float(_hold_targets.size())
	var config: GameConfig = _spawner.get_config()
	var offset: Vector3 = target - global_position
	# A spring that grows with mass, plus damping so it settles instead of wobbling.
	apply_central_force((offset * HOLD_STIFFNESS - linear_velocity * HOLD_DAMPING) * mass)
	if offset.length() > config.hold_break_distance:
		_stuck_seconds += delta
		if _stuck_seconds > HOLD_BREAK_SECONDS:
			_stuck_seconds = 0.0
			_spawner.release_all(self)
	else:
		_stuck_seconds = 0.0


## Client: the local holder moves its copy to the hold point; everyone else follows snapshots.
func _client_update(delta: float) -> void:
	if _predicting:
		var motion: Vector3 = _predicted_target - global_position
		# Stop at walls instead of passing through them.
		var collision: KinematicCollision3D = move_and_collide(motion, false, 0.001, true)
		if collision != null:
			global_position += collision.get_travel()
		return
	if not _has_snapshot:
		return
	var weight: float = 1.0 - exp(-SNAPSHOT_SMOOTHING * delta)
	if global_position.distance_to(_snap_position) > SNAPSHOT_SNAP_DISTANCE:
		global_position = _snap_position
	else:
		global_position = global_position.lerp(_snap_position, weight)
	global_basis = Basis(global_basis.get_rotation_quaternion().slerp(_snap_rotation, weight))


func _on_sleeping_state_changed() -> void:
	if sleeping and multiplayer.is_server() and _spawner != null \
			and global_position.y > _spawner.get_config().out_of_world_y + SAFE_HEIGHT_MARGIN:
		_safe_position = global_position

